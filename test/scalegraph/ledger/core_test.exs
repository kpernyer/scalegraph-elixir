defmodule Scalegraph.Ledger.CoreTest do
  use ExUnit.Case, async: false

  alias Scalegraph.Ledger.Core
  alias Scalegraph.Storage.Schema

  setup do
    # Ensure Mnesia is running and clear tables for each test
    Schema.init()
    Schema.clear_all()
    :ok
  end

  describe "create_account/3" do
    test "creates account with initial balance" do
      assert {:ok, account} = Core.create_account("acc1", 1000)
      assert account.id == "acc1"
      assert account.balance == 1000
    end

    test "creates account with zero balance by default" do
      assert {:ok, account} = Core.create_account("acc2")
      assert account.balance == 0
    end

    test "fails to create duplicate account" do
      assert {:ok, _} = Core.create_account("acc1", 100)
      assert {:error, :account_exists} = Core.create_account("acc1", 200)
    end
  end

  describe "get_account/1" do
    test "returns account if exists" do
      {:ok, _} = Core.create_account("acc1", 500)
      assert {:ok, account} = Core.get_account("acc1")
      assert account.balance == 500
    end

    test "returns error for non-existent account" do
      assert {:error, :not_found} = Core.get_account("nonexistent")
    end
  end

  describe "credit/3" do
    test "adds funds to account" do
      {:ok, _} = Core.create_account("acc1", 100)
      assert {:ok, tx} = Core.credit("acc1", 50, "deposit")
      assert tx.type == "credit"

      {:ok, account} = Core.get_account("acc1")
      assert account.balance == 150
    end
  end

  describe "debit/3" do
    test "subtracts funds from account" do
      {:ok, _} = Core.create_account("acc1", 100)
      assert {:ok, tx} = Core.debit("acc1", 30, "withdrawal")
      assert tx.type == "debit"

      {:ok, account} = Core.get_account("acc1")
      assert account.balance == 70
    end

    test "fails with insufficient funds" do
      {:ok, _} = Core.create_account("acc1", 50)
      assert {:error, {:insufficient_funds, _}} = Core.debit("acc1", 100, "overdraft")

      # Balance unchanged
      {:ok, account} = Core.get_account("acc1")
      assert account.balance == 50
    end
  end

  describe "transfer/2" do
    test "atomic two-party transfer" do
      {:ok, _} = Core.create_account("alice", 1000)
      {:ok, _} = Core.create_account("bob", 500)

      entries = [
        # debit alice
        {"alice", -200},
        # credit bob
        {"bob", 200}
      ]

      assert {:ok, tx} = Core.transfer(entries, "payment")
      assert tx.type == "transfer"
      assert length(tx.entries) == 2

      {:ok, alice} = Core.get_account("alice")
      {:ok, bob} = Core.get_account("bob")
      assert alice.balance == 800
      assert bob.balance == 700
    end

    test "multi-party atomic transfer" do
      {:ok, _} = Core.create_account("alice", 1000)
      {:ok, _} = Core.create_account("bob", 500)
      {:ok, _} = Core.create_account("charlie", 300)
      {:ok, _} = Core.create_account("fees", 0)

      # Alice pays Bob 200, with 10 going to fees
      entries = [
        {"alice", -210},
        {"bob", 200},
        {"fees", 10}
      ]

      assert {:ok, _tx} = Core.transfer(entries, "payment_with_fee")

      {:ok, alice} = Core.get_account("alice")
      {:ok, bob} = Core.get_account("bob")
      {:ok, fees} = Core.get_account("fees")

      assert alice.balance == 790
      assert bob.balance == 700
      assert fees.balance == 10
    end

    test "transfer fails atomically if any account has insufficient funds" do
      {:ok, _} = Core.create_account("alice", 100)
      {:ok, _} = Core.create_account("bob", 50)

      entries = [
        # More than alice has
        {"alice", -500},
        {"bob", 500}
      ]

      assert {:error, {:insufficient_funds, _}} = Core.transfer(entries, "failed")

      # Both balances unchanged
      {:ok, alice} = Core.get_account("alice")
      {:ok, bob} = Core.get_account("bob")
      assert alice.balance == 100
      assert bob.balance == 50
    end

    test "transfer fails if account not found" do
      {:ok, _} = Core.create_account("alice", 100)

      entries = [
        {"alice", -50},
        {"nonexistent", 50}
      ]

      assert {:error, {:not_found, _}} = Core.transfer(entries, "failed")

      # Alice balance unchanged
      {:ok, alice} = Core.get_account("alice")
      assert alice.balance == 100
    end
  end
end
