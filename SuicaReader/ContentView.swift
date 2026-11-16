
import SwiftUI

struct ContentView: View {

    @StateObject private var reader = SuicaReader()

    var body: some View {

        NavigationStack {

            ScrollView {

                VStack(spacing: 24) {

                    // 残高表示
                    VStack(spacing: 8) {

                        Text("現在の残高")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        if let balance = reader.balance {
                            Text("¥\(balance)")
                                .font(.system(
                                    size: 42,
                                    weight: .bold
                                ))
                        } else {
                            Text("------")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                    .background(
                        Color.blue.opacity(0.1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    // 読み取りボタン
                    Button {
                        reader.startScan()
                    } label: {

                        HStack {
                            Image(systemName: "wave.3.right")
                            Text("Suicaを読み取る")
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(reader.isReading)

                    Text(reader.result)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // 利用履歴
                    VStack(alignment: .leading, spacing: 12) {

                        Text("利用履歴")
                            .font(.title2)
                            .bold()

                        if reader.history.isEmpty {

                            Text("まだ履歴がありません")
                                .foregroundStyle(.secondary)

                        } else {

                            ForEach(reader.history) { item in

                                VStack(alignment: .leading, spacing: 6) {

                                    HStack {
                                        Text(item.date)
                                            .font(.headline)

                                        Spacer()

                                        Text(
                                            item.amount.map {
                                                $0 < 0 ? "入金 ¥\(-$0)" : "利用 ¥\($0)"
                                            } ?? "金額不明"
                                        )
                                        .font(.headline)
                                    }

                                    Text("処理コード: \(item.processCode)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Divider()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Suica Reader")
        }
    }
}
