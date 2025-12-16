# CLI Functional Improvements

This document outlines suggested functional improvements to make the CLI easier to navigate and better at explaining the data model.

## Navigation Improvements

### 1. Breadcrumb Navigation
**Problem:** When drilling down from Participants → Accounts, users lose context about where they are in the hierarchy.

**Solution:**
- Add a breadcrumb bar showing: `Participants > [Participant Name] > Accounts`
- Make breadcrumb segments clickable (or navigable with keyboard)
- Show current context at all times

**Implementation:**
- Add `breadcrumb: Vec<String>` to `App` state
- Update breadcrumb when navigating: `Participants` → `Participant Detail` → `Accounts`
- Render breadcrumb in a dedicated area above main content

### 2. Back Button / Navigation Stack
**Problem:** No way to go back after selecting a participant to view accounts.

**Solution:**
- Add `Back` key (`b` or `Esc` in detail views) to return to previous view
- Maintain navigation stack: `Vec<View>` with context
- Show "← Back" hint in status bar when applicable

**Implementation:**
```rust
pub struct App {
    // ... existing fields
    navigation_stack: Vec<(View, Option<String>)>, // View + optional context (e.g., participant_id)
}

pub fn go_back(&mut self) {
    if let Some((view, context)) = self.navigation_stack.pop() {
        self.current_view = view;
        // Restore context if needed
    }
}
```

### 3. Consistent Tab Navigation
**Problem:** Tab key behavior is confusing - cycles suggestions in Transfer view but switches views elsewhere.

**Solution:**
- Use `Tab`/`Shift+Tab` consistently for view switching
- Use `Ctrl+Tab` or `Ctrl+Space` for cycling suggestions in Transfer view
- Or use `↑`/`↓` for suggestions and keep Tab for view switching

**Recommended:** Keep Tab for view switching, use arrow keys for suggestion cycling.

### 4. Direct View Access with Number Keys
**Current:** Number keys (1-4) work but only when not in Transfer view.

**Improvement:**
- Make number keys work everywhere (including Transfer view when not typing)
- Add visual indicators in tab bar: `[1] Participants [2] Accounts [3] Transfer [4] History`
- Show keyboard shortcuts in help text

### 5. Search and Filter
**Problem:** No way to search participants or accounts when lists are long.

**Solution:**
- Add `/` key to enter search mode
- Filter participants by name, role, or ID
- Filter accounts by participant, type, or ID
- Show search query in status bar: `Search: beauty_`
- Highlight matching text in results

**Implementation:**
```rust
pub struct App {
    // ... existing fields
    search_mode: bool,
    search_query: String,
    filtered_participants: Vec<ParticipantInfo>,
    filtered_accounts: Vec<AccountInfo>,
}
```

## Data Model Understanding

### 6. Account ID Format Explanation
**Problem:** Account IDs like `beauty_hosting:operating` aren't explained in the UI.

**Solution:**
- Add tooltip/help text explaining format: `{participant_id}:{account_type}`
- Show this in Transfer view when typing account IDs
- Add legend/help panel accessible with `?` key

**Implementation:**
- Add help overlay that shows:
  ```
  Account ID Format: {participant_id}:{account_type}
  
  Examples:
    beauty_hosting:operating
    seb:escrow
    schampo_etc:receivables
  
  Account Types:
    operating    - Main business account
    receivables  - Incoming payments
    payables     - Outgoing payments
    escrow       - Held funds
    fees         - Fee collection
    usage        - Pay-per-use tracking
  ```

### 7. Participant Detail View
**Problem:** No way to see full participant information.

**Solution:**
- Add detail view accessible by pressing `Enter` on a participant
- Show: Name, ID, Role, Services, Account Count, Total Balance
- Show all accounts for this participant in the detail view
- Allow navigation to accounts from detail view

**Implementation:**
```rust
pub enum View {
    Participants,
    ParticipantDetail(String), // participant_id
    Accounts,
    Transfer,
    History,
}
```

### 8. Account Detail View
**Problem:** No way to see account details or transaction history for an account.

**Solution:**
- Add account detail view (press `Enter` on account in Accounts view)
- Show: Account ID, Type, Balance, Participant, Created Date
- Show recent transactions affecting this account
- Allow filtering transactions by account

**Implementation:**
- Add `View::AccountDetail(String)` // account_id
- Load transactions filtered by account_id
- Show transaction entries with this account highlighted

### 9. Transaction Detail View
**Problem:** History view only shows summary strings, not full transaction details.

**Solution:**
- Add transaction detail view (press `Enter` on transaction in History)
- Show: Transaction ID, Type, Timestamp, Reference
- Show all entries in a table format:
  ```
  Account              Amount      Balance Change
  ──────────────────────────────────────────────
  beauty_hosting:payables  -500.00    -500.00
  schampo_etc:receivables  +500.00    +500.00
  ```
- Show participant names for each account
- Color-code debits (red) and credits (green)

### 10. Visual Relationship Indicators
**Problem:** No visual indication of relationships between participants, accounts, and transactions.

**Solution:**
- In Accounts view, show participant name next to account ID
- In Transaction History, show participant names, not just account IDs
- Add relationship lines or grouping in detail views
- Show "Related Accounts" in account detail view

**Example Transaction Display:**
```
[abc123] Transfer | 2024-01-15 10:30:00
From: Beauty Hosting (beauty_hosting:payables) -500.00
To:   Schampo etc (schampo_etc:receivables)    +500.00
Ref: order_12345
```

### 11. Account Type Legend
**Problem:** Account types aren't explained in the UI.

**Solution:**
- Add `?` key to show help overlay
- Include account type descriptions
- Show account type icons or colors
- Add tooltip on hover (if mouse support enabled)

### 12. Balance Aggregation
**Problem:** No way to see total balance across all accounts for a participant.

**Solution:**
- In Participant Detail view, show:
  - Total balance across all accounts
  - Balance by account type
  - Account count by type
- In Accounts view, show subtotals when filtered by participant

## Enhanced Features

### 13. Transaction History Improvements
**Current:** Shows only basic transaction info.

**Enhancements:**
- Add filters: by participant, by account, by date range
- Add sorting: newest first, oldest first, by amount
- Show transaction count and total volume
- Group transactions by date
- Show transaction type icons

**Implementation:**
```rust
pub struct HistoryFilters {
    participant_id: Option<String>,
    account_id: Option<String>,
    transaction_type: Option<String>,
    limit: usize,
}
```

### 14. Multi-Party Transfer Support
**Problem:** Transfer form only supports 2-party transfers, but the system supports multi-party.

**Solution:**
- Add "Add Entry" button to transfer form
- Allow adding multiple debit/credit entries
- Show entry list with ability to remove entries
- Validate that sum is reasonable (warn if not zero, but allow)
- Show preview of all entries before submission

**UI Flow:**
```
Transfer Form:
  Entry 1: [beauty_hosting:payables] [-500.00] [Remove]
  Entry 2: [schampo_etc:receivables] [+500.00] [Remove]
  [+ Add Entry]
  
  Reference: [order_12345]
  
  Total: 0.00 (balanced)
```

### 15. Real-time Balance Updates
**Problem:** Balances don't update automatically after transfers.

**Solution:**
- Auto-refresh accounts after successful transfer
- Show loading indicator during refresh
- Highlight changed balances
- Add manual refresh with `r` key (already exists, but make it more obvious)

### 16. Keyboard Shortcuts Reference
**Problem:** Keyboard shortcuts are scattered in status bar.

**Solution:**
- Add `?` key to show full keyboard shortcuts overlay
- Organize by category: Navigation, Actions, Search
- Make it searchable or scrollable
- Show context-sensitive shortcuts

**Example Help Overlay:**
```
┌─ Keyboard Shortcuts ─────────────────────────────┐
│ Navigation:                                       │
│   1-4          Switch to view                    │
│   Tab          Next view                          │
│   Shift+Tab    Previous view                      │
│   ←/→          Switch view                       │
│   b            Back (in detail views)            │
│                                                 │
│ List Navigation:                                 │
│   ↑/↓, j/k     Move selection                    │
│   Home/End     First/Last item                   │
│   Enter        Select/View details                │
│                                                 │
│ Search:                                         │
│   /            Enter search mode                 │
│   Esc          Exit search                       │
│                                                 │
│ Actions:                                        │
│   r            Refresh data                      │
│   q            Quit                              │
│   ?            Show this help                    │
└─────────────────────────────────────────────────┘
```

### 17. Status Messages and Notifications
**Problem:** Success/error messages are only shown in Transfer view.

**Solution:**
- Add global notification system
- Show toast-style messages for all operations
- Auto-dismiss after 3 seconds
- Show error details in a dismissible panel
- Add notification history

### 18. Data Export
**Problem:** No way to export data for analysis.

**Solution:**
- Add `e` key to export current view data
- Export formats: JSON, CSV
- Export participants, accounts, or transactions
- Save to file or copy to clipboard

### 19. Configuration
**Problem:** No way to customize behavior.

**Solution:**
- Add config file support (TOML or JSON)
- Allow setting: default view, refresh interval, date format
- Add command-line flags for common settings
- Persist preferences

### 20. Better Error Handling
**Problem:** Errors are shown as plain text strings.

**Solution:**
- Format errors with context
- Show actionable error messages
- Add "Retry" option for failed operations
- Show error codes and suggestions

**Example:**
```
✗ Transfer Failed

Error: Insufficient funds in account 'beauty_hosting:payables'
Current balance: 100.00
Requested amount: 500.00
Shortfall: 400.00

[Retry] [View Account] [Cancel]
```

## UI/UX Polish

### 21. Loading States
**Current:** Simple "Loading..." text.

**Improvement:**
- Show progress indicators for long operations
- Show what's being loaded: "Loading participants..."
- Add skeleton screens
- Show estimated time remaining

### 22. Empty States
**Problem:** Empty lists just show "No items" text.

**Solution:**
- Add helpful empty state messages
- Show suggestions: "No participants. Run `mix run -e 'Scalegraph.Seed.run()'` to seed data."
- Add icons or ASCII art
- Show quick actions

### 23. Visual Hierarchy
**Problem:** All information has equal visual weight.

**Solution:**
- Use typography hierarchy (bold for important, gray for secondary)
- Add visual separators between sections
- Use colors more consistently (green=positive, red=negative, yellow=warning)
- Add icons for common actions

### 24. Responsive Layout
**Problem:** Layout might break on small terminals.

**Solution:**
- Detect terminal size and adjust layout
- Show minimum size warning
- Collapse less important information on small screens
- Add horizontal scrolling for wide tables

## Implementation Priority

### High Priority (Core Navigation & Understanding)
1. ✅ Breadcrumb navigation (#1)
2. ✅ Back button (#2)
3. ✅ Participant detail view (#7)
4. ✅ Account detail view (#8)
5. ✅ Transaction detail view (#9)
6. ✅ Account ID format explanation (#6)

### Medium Priority (Enhanced Usability)
7. ✅ Search and filter (#5)
8. ✅ Visual relationship indicators (#10)
9. ✅ Consistent tab navigation (#3)
10. ✅ Keyboard shortcuts reference (#16)
11. ✅ Transaction history improvements (#13)

### Low Priority (Nice to Have)
12. Multi-party transfer support (#14)
13. Data export (#18)
14. Configuration (#19)
15. Better error handling (#20)

## Technical Considerations

### State Management
- Consider using a state machine for view transitions
- Add undo/redo capability for form inputs
- Cache data to reduce server calls

### Performance
- Lazy load transaction history (pagination)
- Debounce search input
- Cache participant/account data
- Show loading states for async operations

### Testing
- Add integration tests for navigation flows
- Test keyboard shortcuts
- Test error handling
- Test with various terminal sizes

## Example: Improved Navigation Flow

```
Participants View
  ↓ (Enter on participant)
Participant Detail View
  ↓ (View Accounts button or Enter)
Accounts View (filtered by participant)
  ↓ (Enter on account)
Account Detail View
  ↓ (View Transactions)
Transaction History (filtered by account)
  ↓ (Enter on transaction)
Transaction Detail View
  ↓ (b to go back)
Transaction History
  ↓ (b to go back)
Account Detail View
  ↓ (b to go back)
Accounts View
  ↓ (b to go back)
Participant Detail View
  ↓ (b to go back)
Participants View
```

This creates a clear hierarchy and allows users to drill down and back up through the data model.

