import SwiftUI
import SwiftData

struct EditExpenseView: View {
    @Bindable var expense: Expense
    @Bindable var trip: Trip
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel

    @State private var title: String
    @State private var payer: Member?
    @State private var includedMembers: Set<Member>
    @State private var splitMode: SplitMode
    @State private var amountInput: String
    @State private var customShares: [Member: Decimal]
    @State private var customShareInputs: [Member: String]
    @State private var showAlert = false
    @State private var alertMessage = ""

    var activeUid: String? {
        authVM.linkedOwnerUid ?? authVM.user?.uid
    }

    init(expense: Expense, trip: Trip) {
        self.expense = expense
        self.trip = trip

        _title = State(initialValue: expense.title)
        _payer = State(initialValue: expense.paidBy)
        let members = Set(expense.splits.map(\.member))
        _includedMembers = State(initialValue: members)

        let sumShares = expense.splits.map(\.share).reduce(0, +)
        if sumShares > 0.99, sumShares < 1.01,
           Set(expense.splits.map(\.share)).count == 1
        {
            _splitMode = State(initialValue: .equal)
        } else {
            _splitMode = State(initialValue: .custom)
        }

        _amountInput = State(initialValue: expense.amount.description)

        // Заполняем customShares и customShareInputs для ручного режима
        var cs: [Member: Decimal] = [:]
        var csi: [Member: String] = [:]
        for split in expense.splits {
            let member = split.member
            let memberSum = (expense.amount * split.share).rounded(2)
            cs[member] = memberSum
            csi[member] = memberSum > 0 ? memberSum.description : ""
        }
        _customShares = State(initialValue: cs)
        _customShareInputs = State(initialValue: csi)
    }

    var body: some View {
        NavigationStack {
            Form {
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

                Section(header: Text("Описание")) {
                    TextField("Название траты", text: $title)
                        .accessibilityLabel(Text("Название траты"))
                        .accessibilityHint(Text("Введите описание расхода"))
                    if splitMode == .equal {
                        TextField("Сумма", text: $amountInput)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel(Text("Сумма траты"))
                            .accessibilityHint(Text("Введите сумму расхода"))
                    } else {
                        HStack {
                            Text("Сумма")
                            Spacer()
                            Text(totalCustomShare > 0 ? totalCustomShare.formatted() : "0" + " " + trip.currency)
                                .foregroundColor(.primary)
                        }
                    }
                }
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
            .navigationTitle("Редактировать трату")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") { save() }
                        .disabled(!canSave)
                        .accessibilityLabel(Text("Сохранить трату"))
                        .accessibilityHint(Text("Сохранить изменения расхода для поездки"))
                }
            }
            .onChange(of: includedMembers) {
                for member in includedMembers where customShareInputs[member] == nil {
                    customShareInputs[member] = ""
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Ошибка"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }

        }
    }

    private func save() {
        guard let payer = payer, !title.isEmpty, !includedMembers.isEmpty else {
            alertMessage = "Пожалуйста, заполните все поля и выберите плательщика."
            showAlert = true
            return
        }
        let total: Decimal
        let splits: [Split]
        if splitMode == .equal {
            guard let price = Decimal(string: amountInput), price > 0 else {
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
        expense.title = title
        expense.amount = total
        expense.paidBy = payer
        expense.splits = splits
        dismiss()
    }

    private var canSave: Bool {
        guard !title.isEmpty,
              !includedMembers.isEmpty,
              payer != nil
        else { return false }
        if splitMode == .equal {
            return Decimal(string: amountInput).map { $0 > 0 } ?? false
        } else {
            let filled = includedMembers.allSatisfy { member in
                if let input = customShareInputs[member], let cleaned = Self.cleanDecimalInput(input), let value = Decimal(string: cleaned), value > 0 {
                    return true
                } else {
                    return false
                }
            }
            return filled && totalCustomShare > 0
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

// Для удобства округления суммы при заполнении поля для участников:
extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var d = self
        var result = Decimal()
        NSDecimalRound(&result, &d, scale, .plain)
        return result
    }
}
