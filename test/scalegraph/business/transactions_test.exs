defmodule Scalegraph.Business.TransactionsTest do
  use ExUnit.Case, async: false

  alias Scalegraph.Business.Transactions
  alias Scalegraph.Business.Contracts
  alias Scalegraph.Ledger.Core
  alias Scalegraph.Participant.Core, as: ParticipantCore
  alias Scalegraph.Storage.Schema

  setup do
    # Ensure Mnesia is running and clear tables for each test
    Schema.init()
    Schema.clear_all()

    # Create participants
    {:ok, _} = ParticipantCore.create_participant("supplier1", "Supplier One", :supplier, %{})
    {:ok, _} = ParticipantCore.create_participant("buyer1", "Buyer One", :ecosystem_partner, %{})
    {:ok, _} = ParticipantCore.create_participant("lender1", "Lender One", :banking_partner, %{})
    {:ok, _} = ParticipantCore.create_participant("borrower1", "Borrower One", :ecosystem_partner, %{})
    {:ok, _} = ParticipantCore.create_participant("payer1", "Payer One", :ecosystem_partner, %{})
    {:ok, _} = ParticipantCore.create_participant("access_provider1", "Access Provider", :access_provider, %{})

    # Create accounts
    {:ok, _} = ParticipantCore.create_participant_account("supplier1", :operating, 0)
    {:ok, _} = ParticipantCore.create_participant_account("supplier1", :receivables, 0)
    {:ok, _} = ParticipantCore.create_participant_account("buyer1", :operating, 10_000)
    {:ok, _} = ParticipantCore.create_participant_account("buyer1", :payables, 0)
    {:ok, _} = ParticipantCore.create_participant_account("lender1", :operating, 100_000)
    {:ok, _} = ParticipantCore.create_participant_account("lender1", :receivables, 0)
    {:ok, _} = ParticipantCore.create_participant_account("borrower1", :operating, 0)
    {:ok, _} = ParticipantCore.create_participant_account("borrower1", :payables, 0)
    {:ok, _} = ParticipantCore.create_participant_account("payer1", :operating, 5_000)
    {:ok, _} = ParticipantCore.create_participant_account("access_provider1", :fees, 0)

    :ok
  end

  describe "purchase_invoice/4" do
    test "creates invoice and ledger transaction" do
      assert {:ok, result} = Transactions.purchase_invoice("supplier1", "buyer1", 5_000, "INV-001")

      assert result.transaction_id != nil
      assert result.invoice_ref == "INV-001"
      assert result.amount == 5_000

      # Verify ledger transaction
      {:ok, supplier_receivables} = Core.get_balance("supplier1:receivables")
      {:ok, buyer_payables} = Core.get_balance("buyer1:payables")

      assert supplier_receivables == 5_000
      assert buyer_payables == -5_000

      # Verify invoice contract was created
      assert {:ok, invoices} = Contracts.list_invoices(supplier_id: "supplier1")
      assert length(invoices) == 1
      assert hd(invoices).reference == "INV-001"
    end

    test "fails if accounts don't exist" do
      assert {:error, {:not_found, _}} =
               Transactions.purchase_invoice("nonexistent", "buyer1", 5_000, "INV-002")
    end
  end

  describe "pay_invoice/4" do
    test "pays invoice and updates contract" do
      # Create invoice first
      {:ok, invoice_result} =
        Transactions.purchase_invoice("supplier1", "buyer1", 3_000, "INV-003")

      # Pay invoice
      assert {:ok, payment_result} =
               Transactions.pay_invoice("supplier1", "buyer1", 3_000, "PAY-003")

      assert payment_result.transaction_id != nil
      assert payment_result.payment_ref == "PAY-003"

      # Verify ledger balances
      {:ok, supplier_operating} = Core.get_balance("supplier1:operating")
      {:ok, buyer_operating} = Core.get_balance("buyer1:operating")
      {:ok, supplier_receivables} = Core.get_balance("supplier1:receivables")
      {:ok, buyer_payables} = Core.get_balance("buyer1:payables")

      assert supplier_operating == 3_000
      assert buyer_operating == 7_000  # 10_000 - 3_000
      assert supplier_receivables == 0
      assert buyer_payables == 0

      # Verify invoice contract was updated
      {:ok, invoice} = Contracts.get_invoice(invoice_result.invoice_id)
      assert invoice.status == :paid
    end

    test "fails with insufficient funds" do
      # Create invoice
      {:ok, _} = Transactions.purchase_invoice("supplier1", "buyer1", 15_000, "INV-004")

      # Try to pay with insufficient funds
      assert {:error, {:insufficient_funds, _, _, _}} =
               Transactions.pay_invoice("supplier1", "buyer1", 15_000, "PAY-004")
    end
  end

  describe "access_payment/4" do
    test "processes access payment" do
      assert {:ok, result} =
               Transactions.access_payment("payer1", "access_provider1", 500, reference: "ACC-001")

      assert result.transaction_id != nil
      assert result.amount == 500

      # Verify ledger balances
      {:ok, payer_operating} = Core.get_balance("payer1:operating")
      {:ok, provider_fees} = Core.get_balance("access_provider1:fees")

      assert payer_operating == 4_500  # 5_000 - 500
      assert provider_fees == 500
    end

    test "processes access payment with platform fee" do
      # Create platform participant and account
      {:ok, _} = ParticipantCore.create_participant("platform1", "Platform", :ecosystem_orchestrator, %{})
      {:ok, _} = ParticipantCore.create_participant_account("platform1", :fees, 0)

      assert {:ok, result} =
               Transactions.access_payment(
                 "payer1",
                 "access_provider1",
                 1_000,
                 reference: "ACC-002",
                 platform_id: "platform1",
                 platform_fee: 100
               )

      assert result.platform_fee == 100

      # Verify ledger balances
      {:ok, payer_operating} = Core.get_balance("payer1:operating")
      {:ok, provider_fees} = Core.get_balance("access_provider1:fees")
      {:ok, platform_fees} = Core.get_balance("platform1:fees")

      assert payer_operating == 4_000  # 5_000 - 1_000
      assert provider_fees == 900  # 1_000 - 100
      assert platform_fees == 100
    end

    test "fails with insufficient funds" do
      assert {:error, {:insufficient_funds, _, _, _}} =
               Transactions.access_payment("payer1", "access_provider1", 10_000, reference: "ACC-003")
    end
  end

  describe "create_loan/4" do
    test "creates loan and ledger transaction" do
      assert {:ok, result} = Transactions.create_loan("lender1", "borrower1", 20_000, "LOAN-001")

      assert result.transaction_id != nil
      assert result.loan_ref == "LOAN-001"
      assert result.amount == 20_000

      # Verify ledger balances
      {:ok, lender_operating} = Core.get_balance("lender1:operating")
      {:ok, borrower_operating} = Core.get_balance("borrower1:operating")
      {:ok, lender_receivables} = Core.get_balance("lender1:receivables")
      {:ok, borrower_payables} = Core.get_balance("borrower1:payables")

      assert lender_operating == 80_000  # 100_000 - 20_000
      assert borrower_operating == 20_000
      assert lender_receivables == 20_000
      assert borrower_payables == -20_000

      # Verify loan contract was created
      assert {:ok, loans} = Contracts.list_loans(lender_id: "lender1")
      assert length(loans) == 1
      assert hd(loans).reference == "LOAN-001"
    end

    test "fails with insufficient funds" do
      assert {:error, {:insufficient_funds, _, _, _}} =
               Transactions.create_loan("lender1", "borrower1", 200_000, "LOAN-002")
    end
  end

  describe "repay_loan/4" do
    test "repays loan and updates contract" do
      # Create loan first
      {:ok, loan_result} = Transactions.create_loan("lender1", "borrower1", 15_000, "LOAN-003")

      # Give borrower some funds
      {:ok, _} = Core.credit("borrower1:operating", 10_000, "funding")

      # Repay loan
      assert {:ok, repay_result} =
               Transactions.repay_loan("lender1", "borrower1", 5_000, "REPAY-003")

      assert repay_result.transaction_id != nil
      assert repay_result.repayment_ref == "REPAY-003"

      # Verify ledger balances
      {:ok, lender_operating} = Core.get_balance("lender1:operating")
      {:ok, borrower_operating} = Core.get_balance("borrower1:operating")
      {:ok, lender_receivables} = Core.get_balance("lender1:receivables")
      {:ok, borrower_payables} = Core.get_balance("borrower1:payables")

      assert lender_operating == 90_000  # 100_000 - 15_000 (loan) + 5_000 (repayment)
      assert borrower_operating == 20_000  # 15_000 (loan) + 10_000 (funding) - 5_000 (repayment)
      assert lender_receivables == 10_000  # 15_000 (loan) - 5_000 (repayment)
      assert borrower_payables == -10_000  # -15_000 (loan) + 5_000 (repayment)

      # Verify loan contract was updated
      {:ok, loan} = Contracts.get_loan(loan_result.loan_id)
      assert length(loan.repayment_transaction_ids) == 1
    end

    test "fails with insufficient funds" do
      # Create loan (borrower gets 10_000)
      {:ok, _} = Transactions.create_loan("lender1", "borrower1", 10_000, "LOAN-004")

      # Spend the loan money first
      {:ok, _} = Core.debit("borrower1:operating", 10_000, "spent")

      # Now try to repay with insufficient funds
      assert {:error, {:insufficient_funds, _, _, _}} =
               Transactions.repay_loan("lender1", "borrower1", 10_000, "REPAY-004")
    end
  end

  describe "get_outstanding_loans/1" do
    test "returns total outstanding for lender" do
      # Create loans
      {:ok, _} = Transactions.create_loan("lender1", "borrower1", 10_000, "LOAN-005")
      {:ok, _} = Transactions.create_loan("lender1", "borrower1", 5_000, "LOAN-006")

      # Get outstanding loans
      assert {:ok, total} = Transactions.get_outstanding_loans("lender1")
      assert total == 15_000
    end

    test "returns zero if no loans" do
      assert {:ok, total} = Transactions.get_outstanding_loans("lender1")
      assert total == 0
    end
  end

  describe "get_total_debt/1" do
    test "returns total debt for borrower" do
      # Create loans
      {:ok, _} = Transactions.create_loan("lender1", "borrower1", 12_000, "LOAN-007")
      {:ok, _} = Transactions.create_loan("lender1", "borrower1", 8_000, "LOAN-008")

      # Get total debt
      assert {:ok, total} = Transactions.get_total_debt("borrower1")
      assert total == 20_000
    end

    test "returns zero if no debt" do
      assert {:ok, total} = Transactions.get_total_debt("borrower1")
      assert total == 0
    end
  end
end

