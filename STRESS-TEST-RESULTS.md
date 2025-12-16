# Stress Test Results

## Overview

The stress test validates database behavior under concurrent load, verifying:
- ACID transaction properties
- Balance consistency
- Error handling
- Performance metrics
- Negative balance support for receivables/payables

## Test Results Summary

### ✅ Test 1: Concurrent Transfers (Balance Consistency)
- **100 concurrent transfers** between 3 accounts
- **Result**: Balance always conserved (ACID property maintained)
- **Note**: Some failures expected when concurrent transfers attempt to debit the same account simultaneously - this is correct behavior preventing double-spending

### ✅ Test 2: High Volume Transactions (Performance)
- **500 transactions** across 4 accounts
- **Throughput**: ~600-700 transactions/second
- **Result**: All transactions succeed, balances remain consistent

### ✅ Test 3: Negative Balances (Receivables/Payables)
- **100 concurrent invoice creations**
- **Result**: Receivables go positive, payables go negative (as designed)
- **Verification**: Total always balances to zero

### ✅ Test 4: Concurrent Account Creation (Race Conditions)
- **50 concurrent account creations**
- **Result**: All accounts created successfully, no duplicates
- **Verification**: No race conditions detected

### ✅ Test 5: Mixed Workload (Real-world Scenario)
- **200 mixed operations** (payments, invoices, loans, repayments)
- **Throughput**: ~400-500 operations/second
- **Result**: All operations succeed, all balances consistent

## Key Findings

### ✅ Normal Behavior Confirmed

1. **ACID Properties**: All transactions maintain atomicity, consistency, isolation, and durability
2. **Balance Conservation**: Total balances always conserved across all operations
3. **Concurrency Safety**: No race conditions in account creation or updates
4. **Error Handling**: Insufficient funds errors correctly prevent negative balances (except receivables/payables)
5. **Performance**: Sustains 600+ transactions/second under load
6. **Negative Balances**: Receivables and payables correctly support negative balances for tracking obligations

### Expected Behaviors

- **Concurrent Transfer Failures**: When multiple transfers attempt to debit the same account simultaneously, some will fail with insufficient funds. This is **correct behavior** - the database prevents double-spending by enforcing balance checks atomically.

## Running the Stress Test

```bash
elixir scripts/stress_test.exs
```

The test runs independently without starting the gRPC server, making it safe to run while the server is active.

