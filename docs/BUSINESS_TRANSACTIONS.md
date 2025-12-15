# Business Transaction Models

This document describes the high-level business transactions supported by the Scalegraph Ledger.

## Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    Business Layer                                │
│  BusinessService (gRPC)                                         │
│  ├── PurchaseInvoice    - B2B goods delivery                    │
│  ├── PayInvoice         - Settle B2B invoice                    │
│  └── AccessPayment      - Real-time micro-payment               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Ledger Layer                                  │
│  LedgerService (gRPC)                                           │
│  └── Transfer           - Atomic multi-party transaction         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Storage Layer                                 │
│  Mnesia (ACID transactions)                                     │
│  ├── accounts           - Account balances                      │
│  └── transactions       - Audit log                             │
└─────────────────────────────────────────────────────────────────┘
```

## Account Types

| Type | Purpose | Example |
|------|---------|---------|
| `operating` | Day-to-day money (checking account) | Main business account |
| `receivables` | Money owed TO you (A/R) | Unpaid invoices from customers |
| `payables` | Money YOU owe (A/P) | Unpaid bills to suppliers |
| `escrow` | Money held temporarily | During transaction settlement |
| `fees` | Service charges collected | Platform fees, access fees |
| `usage` | Pay-per-use tracking | Equipment rental charges |

### Account ID Convention

```
{participant_id}:{account_type}
```

Examples:
- `salon_glamour:operating` - Salon's main account
- `schampo_etc:receivables` - Money owed to Schampo etc
- `assa_abloy:fees` - ASSA ABLOY's collected access fees

---

## Transaction Type 1: Purchase Invoice (B2B)

### Use Case
A supplier delivers goods to a buyer. The invoice is recorded immediately, payment comes later.

### Example: Shampoo Delivery
```
Schampo etc delivers to Salon Glamour:
- 300 bottles ABC Shine @ 12 USD = 3,600 USD
- VAT 25%                        =   900 USD
- Delivery                       =    50 USD
- TOTAL                          = 4,550 USD (455,000 cents)
```

### Step 1: Create Invoice

**Request: PurchaseInvoice**
```json
{
  "supplier_id": "schampo_etc",
  "buyer_id": "salon_glamour",
  "amount": 455000,
  "reference": "INV-2024-001 ABC Shine 300x400ml"
}
```

**What happens (atomic):**
| Account | Change | Description |
|---------|--------|-------------|
| `schampo_etc:receivables` | +455,000 | Supplier is owed money |
| `salon_glamour:payables` | -455,000 | Buyer owes money |

**Response:**
```json
{
  "transaction_id": "a1b2c3d4...",
  "reference": "INV-2024-001 ABC Shine 300x400ml",
  "amount": 455000,
  "status": "completed",
  "message": "Invoice created for 4550.00"
}
```

### Step 2: Pay Invoice

**Request: PayInvoice**
```json
{
  "supplier_id": "schampo_etc",
  "buyer_id": "salon_glamour",
  "amount": 455000,
  "reference": "PAY-INV-2024-001"
}
```

**What happens (atomic - all 4 entries in one transaction):**
| Account | Change | Description |
|---------|--------|-------------|
| `salon_glamour:operating` | -455,000 | Money leaves buyer |
| `schampo_etc:operating` | +455,000 | Money arrives at supplier |
| `schampo_etc:receivables` | -455,000 | Receivable cleared |
| `salon_glamour:payables` | +455,000 | Payable cleared |

**Response:**
```json
{
  "transaction_id": "e5f6g7h8...",
  "reference": "PAY-INV-2024-001",
  "amount": 455000,
  "status": "completed",
  "message": "Invoice paid: 4550.00"
}
```

### Account Balances After Full Flow

```
Before Invoice:
  schampo_etc:receivables    =      0
  schampo_etc:operating      =  2,500.00
  salon_glamour:payables     =      0
  salon_glamour:operating    =  5,000.00

After Invoice (Step 1):
  schampo_etc:receivables    = +4,550.00  (owed to them)
  schampo_etc:operating      =  2,500.00  (unchanged)
  salon_glamour:payables     = -4,550.00  (they owe)
  salon_glamour:operating    =  5,000.00  (unchanged)

After Payment (Step 2):
  schampo_etc:receivables    =      0     (cleared)
  schampo_etc:operating      =  7,050.00  (+4,550)
  salon_glamour:payables     =      0     (cleared)
  salon_glamour:operating    =    450.00  (-4,550)
```

---

## Transaction Type 2: Access Payment (Micro-transaction)

### Use Case
Real-time payment for access control. When someone uses a temporary key (e.g., to open a door), payment is processed instantly.

### Example: Door Access
```
Salon Glamour staff uses temporary key to access building.
ASSA ABLOY charges 8.00 USD per access.
Beauty Hosting (platform) takes 0.50 USD fee.
```

### Simple Access Payment

**Request: AccessPayment**
```json
{
  "payer_id": "salon_glamour",
  "access_provider_id": "assa_abloy",
  "amount": 800,
  "reference": "DOOR-MAIN-20241215-143022"
}
```

**What happens (atomic):**
| Account | Change | Description |
|---------|--------|-------------|
| `salon_glamour:operating` | -800 | Payer is debited |
| `assa_abloy:fees` | +800 | Access provider receives fee |

**Response:**
```json
{
  "transaction_id": "x1y2z3...",
  "reference": "DOOR-MAIN-20241215-143022",
  "amount": 800,
  "status": "completed",
  "message": "Access granted"
}
```

### Access Payment with Platform Fee

**Request: AccessPayment**
```json
{
  "payer_id": "salon_glamour",
  "access_provider_id": "assa_abloy",
  "amount": 800,
  "reference": "DOOR-MAIN-20241215-143022",
  "platform_id": "beauty_hosting",
  "platform_fee": 50
}
```

**What happens (atomic):**
| Account | Change | Description |
|---------|--------|-------------|
| `salon_glamour:operating` | -800 | Payer is debited (full amount) |
| `assa_abloy:fees` | +750 | Access provider (amount - platform_fee) |
| `beauty_hosting:fees` | +50 | Platform fee |

**Response:**
```json
{
  "transaction_id": "x1y2z3...",
  "reference": "DOOR-MAIN-20241215-143022",
  "amount": 800,
  "platform_fee": 50,
  "status": "completed",
  "message": "Access granted"
}
```

---

## Error Handling

All business transactions return appropriate errors:

| Error | HTTP/gRPC Code | Description |
|-------|----------------|-------------|
| `insufficient_funds` | FAILED_PRECONDITION | Payer doesn't have enough balance |
| `account_not_found` | NOT_FOUND | One of the required accounts doesn't exist |
| `invalid_amount` | INVALID_ARGUMENT | Amount must be positive |

### Example Error Response
```json
{
  "transaction_id": "",
  "reference": "DOOR-MAIN-20241215-143022",
  "amount": 800,
  "status": "failed",
  "message": "Insufficient funds: balance 5.00, need 8.00"
}
```

---

## Atomicity Guarantee

All business transactions are **atomic**:
- Either ALL account entries succeed, or NONE do
- No partial updates are possible
- Powered by Mnesia distributed transactions

### Example: Failed Payment
If `salon_glamour:operating` has insufficient funds during `PayInvoice`:
- ❌ No money moves
- ❌ Receivables are NOT cleared
- ❌ Payables are NOT cleared
- ✅ All accounts remain in their pre-transaction state

---

## gRPC Service Definition

```protobuf
service BusinessService {
  // B2B Purchase flow
  rpc PurchaseInvoice(PurchaseInvoiceRequest) returns (BusinessTransactionResponse);
  rpc PayInvoice(PayInvoiceRequest) returns (BusinessTransactionResponse);

  // Real-time access payment
  rpc AccessPayment(AccessPaymentRequest) returns (BusinessTransactionResponse);
}
```

---

## Future Transaction Types

Planned additions:
- **EquipmentUsage** - Pay-per-use for equipment (Hairgrowers United)
- **Subscription** - Recurring payments
- **Refund** - Reverse a previous transaction
- **Split** - Multi-party payment splitting
