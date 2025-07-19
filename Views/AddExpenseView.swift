import SwiftUI
import SwiftData

struct AddExpenseView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var trip: Trip
    @EnvironmentObject var authVM: AuthViewModel // <-- добавлено

    @State private var title = ""
    @State private var amount = ""
    @State private var payer: Member?
    @State private var includedMembers: Set<Member> = []

    @State private var splitMode: SplitMode = .equal
    @State private var customShares: [Member: Decimal] = [:]
    @State private var customShareInputs: [Member: String] = [:]
    @State private var showAlert = false
    @State private var alertMessage = ""

    var activeUid: String? {
        authVM.linkedOwnerUid ?? authVM.user?.uid
    }

    var body: some View {
        NavigationStack {
            Form {
                // --- Участники ---
                Section(header: Text("Кто участвовал в расходе")) {
                    ForEach(trip.members) { member in
                        Toggle(isOn: Binding(
                            get: { includedMembers.contains(member) },
                            set: { isOn in
                                if isOn {
                                    includedMembers.insert(member)
                                    if customShareInputs[member] == nil {
                                        customShareInputs[member] = ""
                                    }
                                } else {
                                    includedMembers.remove(member)
                                    customShares[member] = nil
                                    customShareInputs[member] = nil
                                }
                            }
                        )) {
                            Text(member.name)
                        }
                        .accessibilityLabel(Text("Участник: \(member.name)"))
                        .accessibilityHint(Text("Включить или выключить участие этого человека в расходе"))
                    }
                }

                // --- Делёж ---
                if !includedMembers.isEmpty {
                    Section(header: Text("Делёж")) {
                        Picker("Метод деления", selection: $splitMode) {
                            ForEach(SplitMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel(Text("Метод деления расходов"))
                        .accessibilityHint(Text("Выберите способ деления суммы между участниками"))
                    }
                }

                // --- Суммы по людям (ручной режим) ---
                if splitMode == .custom && !includedMembers.isEmpty {
                    Section(header: Text("Сумма для каждого")) {
                        ForEach(Array(includedMembers), id: \.self) { member in
                            HStack {
                                Text(member.name)
                                Spacer()
                                TextField("0", text: Binding(
                                    get: { customShareInputs[member] ?? "" },
                                    set: { newValue in
                                        customShareInputs[member] = newValue
                                        if let cleaned = Self.cleanDecimalInput(newValue),
                                           let parsed = Decimal(string: cleaned) {
                                            customShares[member] = parsed
                                        } else {
                                            customShares[member] = nil
                                        }
                                    }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel(Text("Сумма для участника \(member.name)"))
                                .accessibilityHint(Text("Введите индивидуальную сумму для этого участника"))
                                Text(trip.currency)
                            }
                        }
                    }
                }

                // --- Описание и итоговая сумма ---
                Section(header: Text("Описание")) {
                    TextField("Название траты", text: $title)
                        .accessibilityLabel(Text("Название траты"))
                        .accessibilityHint(Text("Введите описание расхода"))
                    if splitMode == .equal {
                        TextField("Сумма", text: $amount)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel(Text("Сумма траты"))
                            .accessibilityHint(Text("Введите сумму расхода"))
                    } else {
                        // В режиме "Ручной" поле не редактируемое, автосчёт суммы
                        HStack {
                            Text("Сумма")
                            Spacer()
                            Text(totalCustomShare > 0 ? totalCustomShare.formatted() : "0" + " " + trip.currency)
                                .foregroundColor(.primary)
                        }
                    }
                }

                // --- Плательщик ---
                Section(header: Text("Плательщик")) {
                    Picker("Кто оплатил?", selection: $payer) {
                        ForEach(trip.members) { member in
                            Text(member.name).tag(Optional(member))
                        }
                    }
                    .accessibilityLabel(Text("Плательщик"))
                    .accessibilityHint(Text("Выберите, кто оплатил этот расход"))
                }
            }
            .navigationTitle("Новая трата")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                        .accessibilityLabel(Text("Отмена добавления траты"))
                        .accessibilityHint(Text("Закрыть форму без сохранения"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") { saveExpense() }
                        .disabled(!canSave)
                        .accessibilityLabel(Text("Сохранить трату"))
                        .accessibilityHint(Text("Сохранить новый расход для поездки"))
                }
            }
            .onChange(of: includedMembers) { // Updated for iOS 17+
                // Гарантируем, что новые участники получают строку ввода
                for member in includedMembers where customShareInputs[member] == nil {
                    customShareInputs[member] = ""
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Ошибка"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func saveExpense() {
        guard let payer = payer,
              !title.isEmpty,
              !includedMembers.isEmpty else {
            alertMessage = "Пожалуйста, заполните все поля и выберите плательщика."
            showAlert = true
            return
        }

        let total: Decimal
        let splits: [Split]
        if splitMode == .equal {
            guard let price = Decimal(string: amount), price > 0 else {
                alertMessage = "Введите корректную сумму больше 0."
                showAlert = true
                return
            }
            total = price
            let share = Decimal(1) / Decimal(includedMembers.count)
            splits = includedMembers.map { Split(member: $0, share: share) }
        } else {
            total = totalCustomShare
            guard total > 0 else {
                alertMessage = "Сумма должна быть больше 0."
                showAlert = true
                return
            }
            let totalShares = includedMembers.map { customShares[$0] ?? 0 }.reduce(0, +)
            splits = includedMembers.map { member in
                let individual = customShares[member] ?? 0
                let share = totalShares > 0 ? individual / totalShares : 0
                return Split(member: member, share: share)
            }
        }
        let expense = Expense(
            title: title,
            amount: total,
            paidBy: payer,
            splits: splits
        )
        trip.expenses.append(expense)
        dismiss()
    }

    private var canSave: Bool {
        guard !title.isEmpty,
              !includedMembers.isEmpty,
              payer != nil
        else { return false }
        if splitMode == .equal {
            return Decimal(string: amount).map { $0 > 0 } ?? false
        } else {
            return totalCustomShare > 0
                && customShares.keys.count == includedMembers.count

        }
    }

    private var totalCustomShare: Decimal {
        customShares
            .filter { includedMembers.contains($0.key) }
            .values
            .compactMap { $0 }
            .reduce(0, +)
    }

    enum SplitMode: String, CaseIterable, Identifiable {
        case equal = "Поровну"
        case custom = "Ручной"
        var id: String { rawValue }
    }

    private static func cleanDecimalInput(_ input: String) -> String? {
        let allowed = "0123456789.,"
        let cleaned = input.filter { allowed.contains($0) }.replacingOccurrences(of: ",", with: ".")
        return cleaned.isEmpty ? nil : cleaned
    }
}
