//
//  SuicaReader.swift
//  SuicaReader
//
//  Created by 学校アカウント on 2026/11/16.
//


import Foundation
import SwiftUI
import CoreNFC
import Combine

// 利用履歴1件分のデータ
struct SuicaHistory: Identifiable {
    let id: Int
    let date: String
    let balance: Int
    let amount: Int?
    let processCode: String
}

// NFC読み取りクラス
final class SuicaReader: NSObject, ObservableObject,
                         NFCTagReaderSessionDelegate {

    @Published var result = "Suicaを読み取ってください"
    @Published var balance: Int?
    @Published var history: [SuicaHistory] = []
    @Published var isReading = false

    private var session: NFCTagReaderSession?

    // MARK: - NFC読み取り開始

    func startScan() {

        guard NFCTagReaderSession.readingAvailable else {
            result = "この端末はNFCに対応していません"
            return
        }

        balance = nil
        history = []
        result = "Suicaをかざしてください"
        isReading = true

        if let newSession = NFCTagReaderSession(
            pollingOption: [.iso18092],
            delegate: self,
            queue: nil
        ) {
            newSession.alertMessage = "iPhoneの上部をSuicaにかざしてください"
            session = newSession
            newSession.begin()
        }
    }

    // MARK: - NFCタグ検出

    func tagReaderSession(
        _ session: NFCTagReaderSession,
        didDetect tags: [NFCTag]
    ) {

        guard let tag = tags.first else {
            session.invalidate(errorMessage: "カードが見つかりません")
            return
        }

        session.connect(to: tag) { error in

            if let error = error {
                session.invalidate(
                    errorMessage: error.localizedDescription
                )
                return
            }

            guard case let .feliCa(felicaTag) = tag else {
                session.invalidate(
                    errorMessage: "FeliCaカードではありません"
                )
                return
            }

            let idm = felicaTag.currentIDm
                .map { String(format: "%02X", $0) }
                .joined()

            DispatchQueue.main.async {
                self.result = "カードを認識しました"
            }

            print("IDm: \(idm)")

            // 残高を読み取る
            self.readBalance(
                tag: felicaTag,
                session: session
            )
        }
    }

    // MARK: - 残高読み取り

    private func readBalance(
        tag: NFCFeliCaTag,
        session: NFCTagReaderSession
    ) {

        // サービスコード 0x008B
        let serviceCode = Data([0x8B, 0x00])

        // ブロック0
        let blockList = [
            Data([0x80, 0x00])
        ]

        tag.readWithoutEncryption(
            serviceCodeList: [serviceCode],
            blockList: blockList
        ) { status1, status2, blockData, error in

            guard error == nil,
                  status1 == 0,
                  status2 == 0,
                  let data = blockData.first,
                  data.count >= 13 else {

                session.invalidate(
                    errorMessage: "残高を読み取れませんでした"
                )
                return
            }

            // 11・12バイト目から残高を取得
            let balance =
                Int(data[11]) |
                (Int(data[12]) << 8)

            DispatchQueue.main.async {
                self.balance = balance
                self.result = "残高を取得しました"
            }

            // 続けて利用履歴を読み取る
            self.readHistory(
                tag: tag,
                session: session
            )
        }
    }

    // MARK: - 利用履歴読み取り

    private func readHistory(
        tag: NFCFeliCaTag,
        session: NFCTagReaderSession
    ) {

        // サービスコード 0x090F
        let serviceCode = Data([0x0F, 0x09])

        var records: [Data] = []

        // 1ブロックずつ順番に読み取る
        func readNext(_ index: Int) {

            // 最大20件
            if index >= 20 {

                DispatchQueue.main.async {
                    let parsed = records.enumerated().map {
                        index, data in
                        self.parseHistory(data, id: index)
                    }

                    self.history = parsed.enumerated().map { index, item in

                        let amount: Int?

                        if index + 1 < parsed.count {
                            amount = parsed[index + 1].balance - item.balance
                        } else {
                            amount = nil
                        }

                        return SuicaHistory(
                            id: item.id,
                            date: item.date,
                            balance: item.balance,
                            amount: amount,
                            processCode: item.processCode
                        )
                    }

                    self.result = "読み取り完了"
                    self.isReading = false
                }

                session.alertMessage = "読み取り完了"
                session.invalidate()
                return
            }

            let blockList = [
                Data([0x80, UInt8(index)])
            ]

            tag.readWithoutEncryption(
                serviceCodeList: [serviceCode],
                blockList: blockList
            ) { status1, status2, blockData, error in

                // エラーまたは読み取り終了
                guard error == nil,
                      status1 == 0,
                      status2 == 0,
                      let data = blockData.first,
                      data.count == 16 else {

                    // ここまで取得できた履歴は表示する
                    DispatchQueue.main.async {
                        self.history = records.enumerated().map {
                            index, data in
                            self.parseHistory(data, id: index)
                        }

                        self.result = records.isEmpty
                            ? "履歴を取得できませんでした"
                            : "一部の履歴を取得しました"

                        self.isReading = false
                    }

                    session.alertMessage = "履歴の読み取りが終了しました"
                    session.invalidate()
                    return
                }

                records.append(data)

                // 次のブロックへ
                readNext(index + 1)
            }
        }

        readNext(0)
    }

    // MARK: - 履歴データ解析

    private func parseHistory(
        _ data: Data,
        id: Int
    ) -> SuicaHistory {

        let dateValue =
            (Int(data[4]) << 8) |
            Int(data[5])

        let year = 2000 + ((dateValue >> 9) & 0x7F)
        let month = (dateValue >> 5) & 0x0F
        let day = dateValue & 0x1F

        let balance =
            Int(data[10]) |
            (Int(data[11]) << 8)

        let date = String(
            format: "%04d/%02d/%02d",
            year, month, day
        )

        let processCode = String(
            format: "%02X",
            data[1]
        )

        return SuicaHistory(
            id: id,
            date: date,
            balance: balance,
            amount: nil,
            processCode: processCode
        )
    }
    
    // MARK: - セッション終了

    func tagReaderSessionDidBecomeActive(
        _ session: NFCTagReaderSession
    ) {
        print("NFC Session Started")
    }

    func tagReaderSession(
        _ session: NFCTagReaderSession,
        didInvalidateWithError error: Error
    ) {
        DispatchQueue.main.async {
            self.isReading = false
        }

        print("NFC Session Ended: \(error.localizedDescription)")
    }
}
