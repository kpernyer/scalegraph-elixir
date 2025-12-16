defmodule Scalegraph.Business.ContractsTest do
  use ExUnit.Case, async: false

  alias Scalegraph.Business.Contracts
  alias Scalegraph.Ledger.Core
  alias Scalegraph.Participant.Core, as: ParticipantCore
  alias Scalegraph.Storage.Schema

  setup do
    # Ensure Mnesia is running and clear tables for each test
    Schema.init()
    Schema.clear_all()
    
    # Create participants for tests
    {:ok, _} = ParticipantCore.create_participant("supplier1", "Supplier", :supplier, %{})
    {:ok, _} = ParticipantCore.create_participant("buyer1", "Buyer", :ecosystem_partner, %{})
    {:ok, _} = ParticipantCore.create_participant("lender1", "Lender", :banking_partner, %{})
    {:ok, _} = ParticipantCore.create_participant("borrower1", "Borrower", :ecosystem_partner, %{})
    
    :ok
  end

  describe "Invoice Contracts" do
    test "create_invoice/6 creates invoice contract" do
      # Create accounts with proper types
      {:ok, _} = ParticipantCore.create_participant_account("supplier1", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("buyer1", :payables, 0)
      
      supplier_receivables = "supplier1:receivables"
      buyer_payables = "buyer1:payables"

      entries = [
        {supplier_receivables, 10000},
        {buyer_payables, -10000}
      ]

      {:ok, tx} = Core.transfer(entries, "INVOICE: INV-001")

      # Create invoice contract
      due_date = System.system_time(:millisecond) + 30 * 24 * 60 * 60 * 1000

      assert {:ok, invoice} =
               Contracts.create_invoice(
                 "supplier1",
                 "buyer1",
                 10_000,
                 tx.id,
                 "INV-001",
                 due_date: due_date
               )

      assert invoice.supplier_id == "supplier1"
      assert invoice.buyer_id == "buyer1"
      assert invoice.amount == 10_000
      assert invoice.status == :pending
      assert invoice.ledger_transaction_id == tx.id
      assert invoice.reference == "INV-001"
    end

    test "get_invoice/1 retrieves invoice by id" do
      # Setup
      {:ok, _} = ParticipantCore.create_participant_account("supplier1", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("buyer1", :payables, 0)
      
      supplier_receivables = "supplier1:receivables"
      buyer_payables = "buyer1:payables"

      {:ok, tx} = Core.transfer([{supplier_receivables, 5000}, {buyer_payables, -5000}], "INV-002")

      {:ok, invoice} = Contracts.create_invoice("supplier1", "buyer1", 5000, tx.id, "INV-002")

      # Get invoice
      assert {:ok, retrieved} = Contracts.get_invoice(invoice.id)
      assert retrieved.id == invoice.id
      assert retrieved.amount == 5000
    end

    test "get_invoice/1 returns error for non-existent invoice" do
      assert {:error, :not_found} = Contracts.get_invoice("nonexistent")
    end

    test "mark_invoice_paid/2 updates invoice status" do
      # Setup
      {:ok, _} = ParticipantCore.create_participant_account("supplier1", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("supplier1", :operating, 0)
      {:ok, _} = ParticipantCore.create_participant_account("buyer1", :payables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("buyer1", :operating, 10_000)
      
      supplier_receivables = "supplier1:receivables"
      buyer_payables = "buyer1:payables"

      {:ok, tx1} = Core.transfer([{supplier_receivables, 3000}, {buyer_payables, -3000}], "INV-003")
      {:ok, invoice} = Contracts.create_invoice("supplier1", "buyer1", 3000, tx1.id, "INV-003")

      # Create payment transaction
      {:ok, tx2} = Core.transfer([{buyer_payables, 3000}, {supplier_receivables, -3000}], "PAY-003")

      # Mark as paid
      assert {:ok, updated} = Contracts.mark_invoice_paid(invoice.id, tx2.id)
      assert updated.status == :paid
      assert updated.paid_at != nil

      # Verify persisted
      {:ok, retrieved} = Contracts.get_invoice(invoice.id)
      assert retrieved.status == :paid
    end

    test "list_invoices/1 filters by supplier" do
      # Setup
      {:ok, _} = ParticipantCore.create_participant_account("supplier1", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("buyer1", :payables, 0)
      
      supplier_receivables = "supplier1:receivables"
      buyer_payables = "buyer1:payables"

      {:ok, tx1} = Core.transfer([{supplier_receivables, 1000}, {buyer_payables, -1000}], "INV-001")
      {:ok, tx2} = Core.transfer([{supplier_receivables, 2000}, {buyer_payables, -2000}], "INV-002")

      {:ok, _} = Contracts.create_invoice("supplier1", "buyer1", 1000, tx1.id, "INV-001")
      {:ok, _} = Contracts.create_invoice("supplier1", "buyer1", 2000, tx2.id, "INV-002")

      # List invoices for supplier
      assert {:ok, invoices} = Contracts.list_invoices(supplier_id: "supplier1")
      assert length(invoices) == 2
    end

    test "list_invoices/1 filters by status" do
      # Setup
      {:ok, _} = ParticipantCore.create_participant_account("supplier1", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("supplier1", :operating, 0)
      {:ok, _} = ParticipantCore.create_participant_account("buyer1", :payables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("buyer1", :operating, 10_000)
      
      supplier_receivables = "supplier1:receivables"
      buyer_payables = "buyer1:payables"

      {:ok, tx1} = Core.transfer([{supplier_receivables, 1000}, {buyer_payables, -1000}], "INV-001")
      {:ok, tx2} = Core.transfer([{supplier_receivables, 2000}, {buyer_payables, -2000}], "INV-002")

      {:ok, invoice1} = Contracts.create_invoice("supplier1", "buyer1", 1000, tx1.id, "INV-001")
      {:ok, _} = Contracts.create_invoice("supplier1", "buyer1", 2000, tx2.id, "INV-002")

      # Mark one as paid
      {:ok, tx3} = Core.transfer([{buyer_payables, 1000}, {supplier_receivables, -1000}], "PAY-001")
      {:ok, _} = Contracts.mark_invoice_paid(invoice1.id, tx3.id)

      # List pending invoices
      assert {:ok, pending} = Contracts.list_invoices(status: :pending)
      assert length(pending) == 1
      assert hd(pending).reference == "INV-002"

      # List paid invoices
      assert {:ok, paid} = Contracts.list_invoices(status: :paid)
      assert length(paid) == 1
      assert hd(paid).reference == "INV-001"
    end
  end

  describe "Loan Contracts" do
    test "create_loan/6 creates loan contract" do
      # Create accounts with proper types
      {:ok, _} = ParticipantCore.create_participant_account("lender1", :operating, 100_000)
      {:ok, _} = ParticipantCore.create_participant_account("lender1", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("borrower1", :operating, 0)
      {:ok, _} = ParticipantCore.create_participant_account("borrower1", :payables, 0)
      
      lender_operating = "lender1:operating"
      borrower_operating = "borrower1:operating"
      lender_receivables = "lender1:receivables"
      borrower_payables = "borrower1:payables"

      entries = [
        {lender_operating, -50_000},
        {borrower_operating, 50_000},
        {lender_receivables, 50_000},
        {borrower_payables, -50_000}
      ]

      {:ok, tx} = Core.transfer(entries, "LOAN: LOAN-001")

      # Create loan contract
      assert {:ok, loan} =
               Contracts.create_loan(
                 "lender1",
                 "borrower1",
                 50_000,
                 tx.id,
                 "LOAN-001",
                 interest_rate: 0.05,
                 repayment_schedule: %{}
               )

      assert loan.lender_id == "lender1"
      assert loan.borrower_id == "borrower1"
      assert loan.principal_amount == 50_000
      assert loan.interest_rate == 0.05
      assert loan.status == :active
      assert loan.disbursement_transaction_id == tx.id
    end

    test "get_loan/1 retrieves loan by id" do
      # Setup
      {:ok, _} = ParticipantCore.create_participant_account("lender1", :operating, 100_000)
      {:ok, _} = ParticipantCore.create_participant_account("lender1", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("borrower1", :operating, 0)
      {:ok, _} = ParticipantCore.create_participant_account("borrower1", :payables, 0)
      
      lender_operating = "lender1:operating"
      borrower_operating = "borrower1:operating"
      lender_receivables = "lender1:receivables"
      borrower_payables = "borrower1:payables"

      {:ok, tx} =
        Core.transfer(
          [
            {lender_operating, -30_000},
            {borrower_operating, 30_000},
            {lender_receivables, 30_000},
            {borrower_payables, -30_000}
          ],
          "LOAN: LOAN-002"
        )

      {:ok, loan} = Contracts.create_loan("lender1", "borrower1", 30_000, tx.id, "LOAN-002")

      # Get loan
      assert {:ok, retrieved} = Contracts.get_loan(loan.id)
      assert retrieved.id == loan.id
      assert retrieved.principal_amount == 30_000
    end

    test "add_loan_repayment/2 records repayment" do
      # Setup
      {:ok, _} = ParticipantCore.create_participant_account("lender1", :operating, 100_000)
      {:ok, _} = ParticipantCore.create_participant_account("lender1", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("borrower1", :operating, 50_000)
      {:ok, _} = ParticipantCore.create_participant_account("borrower1", :payables, 0)
      
      lender_operating = "lender1:operating"
      borrower_operating = "borrower1:operating"
      lender_receivables = "lender1:receivables"
      borrower_payables = "borrower1:payables"

      {:ok, tx1} =
        Core.transfer(
          [
            {lender_operating, -40_000},
            {borrower_operating, 40_000},
            {lender_receivables, 40_000},
            {borrower_payables, -40_000}
          ],
          "LOAN: LOAN-003"
        )

      {:ok, loan} = Contracts.create_loan("lender1", "borrower1", 40_000, tx1.id, "LOAN-003")

      # Create repayment transaction
      {:ok, tx2} =
        Core.transfer(
          [
            {borrower_operating, -5000},
            {lender_operating, 5000},
            {lender_receivables, -5000},
            {borrower_payables, 5000}
          ],
          "REPAY: LOAN-003"
        )

      # Add repayment
      assert {:ok, updated} = Contracts.add_loan_repayment(loan.id, tx2.id)
      assert length(updated.repayment_transaction_ids) == 1
      assert hd(updated.repayment_transaction_ids) == tx2.id

      # Verify persisted
      {:ok, retrieved} = Contracts.get_loan(loan.id)
      assert length(retrieved.repayment_transaction_ids) == 1
    end

    test "list_loans/1 filters by lender" do
      # Setup
      {:ok, _} = ParticipantCore.create_participant("lender2", "Lender 2", :banking_partner, %{})
      {:ok, _} = ParticipantCore.create_participant_account("lender1", :operating, 100_000)
      {:ok, _} = ParticipantCore.create_participant_account("lender1", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("lender2", :operating, 100_000)
      {:ok, _} = ParticipantCore.create_participant_account("lender2", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("borrower1", :operating, 0)
      {:ok, _} = ParticipantCore.create_participant_account("borrower1", :payables, 0)
      
      lender1_operating = "lender1:operating"
      lender2_operating = "lender2:operating"
      borrower_operating = "borrower1:operating"
      lender1_receivables = "lender1:receivables"
      lender2_receivables = "lender2:receivables"
      borrower_payables = "borrower1:payables"

      {:ok, tx1} =
        Core.transfer(
          [
            {lender1_operating, -20_000},
            {borrower_operating, 20_000},
            {lender1_receivables, 20_000},
            {borrower_payables, -20_000}
          ],
          "LOAN: LOAN-004"
        )

      {:ok, tx2} =
        Core.transfer(
          [
            {lender2_operating, -15_000},
            {borrower_operating, 15_000},
            {lender2_receivables, 15_000},
            {borrower_payables, -15_000}
          ],
          "LOAN: LOAN-005"
        )

      {:ok, _} = Contracts.create_loan("lender1", "borrower1", 20_000, tx1.id, "LOAN-004")
      {:ok, _} = Contracts.create_loan("lender2", "borrower1", 15_000, tx2.id, "LOAN-005")

      # List loans for lender1
      assert {:ok, loans} = Contracts.list_loans(lender_id: "lender1")
      assert length(loans) == 1
      assert hd(loans).lender_id == "lender1"
    end

    test "list_loans/1 filters by status" do
      # Setup
      {:ok, _} = ParticipantCore.create_participant_account("lender1", :operating, 100_000)
      {:ok, _} = ParticipantCore.create_participant_account("lender1", :receivables, 0)
      {:ok, _} = ParticipantCore.create_participant_account("borrower1", :operating, 0)
      {:ok, _} = ParticipantCore.create_participant_account("borrower1", :payables, 0)
      
      lender_operating = "lender1:operating"
      borrower_operating = "borrower1:operating"
      lender_receivables = "lender1:receivables"
      borrower_payables = "borrower1:payables"

      {:ok, tx} =
        Core.transfer(
          [
            {lender_operating, -25_000},
            {borrower_operating, 25_000},
            {lender_receivables, 25_000},
            {borrower_payables, -25_000}
          ],
          "LOAN: LOAN-006"
        )

      {:ok, loan} = Contracts.create_loan("lender1", "borrower1", 25_000, tx.id, "LOAN-006")

      # List active loans
      assert {:ok, active} = Contracts.list_loans(status: :active)
      assert length(active) == 1
      assert hd(active).id == loan.id
    end
  end
end

