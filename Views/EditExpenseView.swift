import SwiftUI
import SwiftData

struct EditExpenseView: View {
    @Bindable var expense: Expense
    @Bindable var trip: Trip
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel

    @State private var title: String
    @State private var selectedPayerId: UUID?
    @State private var includedMemberIds: Set<UUID>
    @State private var splitMode: SplitMode
    @State private var amountInput: String
    @State private var customShares: [UUID: Decimal]
    @State private var customShareInputs: [UUID: String]
    @State private var showAlert = false
    @State private var alertMessage = ""

    var members: [Member] { trip.members }

    init(expense: Expense, trip: Trip) {
        self.expense = expense
        self.trip = trip
        _title = State(initialValue: expense.title)
        _selectedPayerId = State(initialValue: expense.paidById)
        _includedMemberIds = State(initialValue: Set(expense.splits.map { $0.memberId }))
        let sumShares = expense.splits.map(\.share).reduce(0, +)
        if sumShares > 0.99, sumShares < 1.01, Set(expense.splits.map(\.share)).count == 1 {
            _splitMode = State(initialValue: .equal)
        } else {
            _splitMode = State(initialValue: .custom)
        }
        _amountInput = State(initialValue: expense.amount.description)
        var cs: [UUID: Decimal] = [:]
        var csi: [UUID: String] = [:]
        for split in expense.splits {
            let memberId = split.memberId
            let memberSum = (expense.amount * split.share).rounded(2)
            cs[memberId] = memberSum
            csi[memberId] = memberSum > 0 ? memberSum.description : ""
        }
        _customShares = State(initialValue: cs)
        _customShareInputs = State(initialValue: csi)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Кто участвовал в расходе")) {
                    ForEach(members) { member in
                        Toggle(isOn: Binding(
                            get: { includedMemberIds.contains(member.id) },
                            set: { isOn in
                                if isOn {
                                    includedMemberIds.insert(member.id)
                                    if customShareInputs[member.id] == nil {
                                        customShareInputs[member.id] = ""
                                    }
                                } else {
                                    includedMemberIds.remove(member.id)
                                    customShares[member.id] = nil
                                    customShareInputs[member.id] = nil
                                }
                            }
                        )) {
                            Text(member.name)
                        }
                    }
                }
                if !includedMemberIds.isEmpty {
                    Section(header: Text("Делёж")) {
                        Picker("Кто оплатил?", selection: $selectedPayerId) {
                            ForEach(members) { member in
                                Text(member.name).tag(Optional(member.id))
                            }
                        }
                        .accessibilityLabel(Text("Плательщик"))
                        .accessibilityHint(Text("Выберите, кто оплатил этот расход"))
                        Picker("Метод деления", selection: $splitMode) {
                            ForEach(SplitMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if splitMode == .custom && !includedMemberIds.isEmpty {
                    Section(header: Text("Сумма для каждого")) {
                        ForEach(Array(includedMemberIds), id: \.self) { memberId in
                            let member = members.first { $0.id == memberId }
                            HStack {
                                Text(member?.name ?? "?")
                                Spacer()
                                TextField("0", text: Binding(
                                    get: { customShareInputs[memberId] ?? "" },
                                    set: { newValue in
                                        customShareInputs[memberId] = newValue
                                        if let cleaned = Self.cleanDecimalInput(newValue), let parsed = Decimal(string: cleaned) {
                                            customShares[memberId] = parsed
                                        } else {
                                            customShares[memberId] = nil
                                        }
                                    }
                                ))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                Text(trip.currency)
                            }
                        }
                    }
                }
                Section(header: Text("Описание")) {
                    TextField("Название траты", text: $title)
                    if splitMode == .equal {
                        TextField("Сумма", text: $amountInput)
                            .keyboardType(.decimalPad)
                    } else {
                        HStack {
                            Text("Сумма")
                            Spacer()
                            Text(totalCustomShare > 0 ? totalCustomShare.formatted() : "0" + " " + trip.currency)
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .navigationTitle("Редактировать трату")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") { save() }
                        .disabled(!canSave)
                }
            }
            .onChange(of: includedMemberIds) {
                for memberId in includedMemberIds where customShareInputs[memberId] == nil {
                    customShareInputs[memberId] = ""
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Ошибка"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }
    private func save() {
        guard let payerId = selectedPayerId, !title.isEmpty, !includedMemberIds.isEmpty else {
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
            let share = Decimal(1) / Decimal(includedMemberIds.count)
            splits = includedMemberIds.map { Split(memberId: $0, share: share) }
        } else {
            total = totalCustomShare
            guard total > 0 else {
                alertMessage = "Сумма должна быть больше 0."
                showAlert = true
                return
            }
            let totalShares = includedMemberIds.map { customShares[$0] ?? 0 }.reduce(0, +)
            splits = includedMemberIds.map { memberId in
                let individual = customShares[memberId] ?? 0
                let share = totalShares > 0 ? individual / totalShares : 0
                return Split(memberId: memberId, share: share)
            }
        }
        expense.title = title
        expense.amount = total
        expense.paidById = payerId
        expense.splits = splits
        dismiss()
    }
    private var canSave: Bool {
        guard !title.isEmpty, !includedMemberIds.isEmpty, selectedPayerId != nil else { return false }
        if splitMode == .equal {
            return Decimal(string: amountInput).map { $0 > 0 } ?? false
        } else {
            let filled = includedMemberIds.allSatisfy { memberId in
                if let input = customShareInputs[memberId], let cleaned = Self.cleanDecimalInput(input), let value = Decimal(string: cleaned), value > 0 {
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
            .filter { includedMemberIds.contains($0.key) }
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
