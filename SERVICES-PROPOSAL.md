# Participant Services Proposal

## Proposed Service Assignments

Based on participant roles and business functions, here's the suggested service mapping:

### Access Providers
- **assa_abloy** (Access Provider)
  - `access_control` - Physical access control systems
  - `door_management` - Door unlock/lock services
  - `security_systems` - Security and monitoring

### Banking Partners
- **seb** (Banking Partner)
  - `financing` - Loan and credit services
  - `payment_processing` - Payment handling
  - `escrow_services` - Escrow account management
  - `settlement` - Financial settlement services

### Ecosystem Partners (Platforms)
- **beauty_hosting** (Ecosystem Partner - Platform)
  - `platform_services` - Core platform functionality
  - `marketplace` - Marketplace operations
  - `fee_collection` - Platform fee management
  - `participant_onboarding` - New participant setup

### Suppliers
- **schampo_etc** (Supplier - Beauty Products)
  - `product_supply` - Product delivery
  - `beauty_products` - Beauty and hair products
  - `inventory_management` - Stock management

- **clipper_oy** (Supplier - Equipment)
  - `product_supply` - Product delivery
  - `equipment_supply` - Hairdressing equipment
  - `inventory_management` - Stock management

### Equipment Providers
- **hairgrowers_united** (Equipment Provider - Pay-per-use)
  - `equipment_rental` - Equipment rental services
  - `pay_per_use` - Usage-based billing
  - `equipment_maintenance` - Maintenance services

### Salons (Ecosystem Partners)
- **salon_glamour** (Ecosystem Partner - Salon)
  - `hair_services` - Hair styling and cutting
  - `beauty_services` - Beauty treatments
  - `customer_services` - Customer-facing services

- **klipp_och_trim** (Ecosystem Partner - Salon)
  - `hair_services` - Hair styling and cutting
  - `family_services` - Family-friendly services
  - `customer_services` - Customer-facing services

## Service Categories

### Core Services
- `financing` - Financial services (loans, credit)
- `payment_processing` - Payment handling
- `access_control` - Physical access systems
- `platform_services` - Platform core functionality

### Supply Chain Services
- `product_supply` - Product delivery
- `equipment_supply` - Equipment delivery
- `inventory_management` - Stock management

### Service Delivery
- `hair_services` - Hair styling services
- `beauty_services` - Beauty treatments
- `equipment_rental` - Equipment rental
- `pay_per_use` - Usage-based services

### Platform Services
- `marketplace` - Marketplace operations
- `fee_collection` - Fee management
- `participant_onboarding` - Onboarding services

## Implementation Plan

1. **Update `priv/seed_data.yaml`**:
   - Add `services` field to each participant
   - List of service identifiers as strings

2. **Update `lib/scalegraph/seed.ex`**:
   - Parse `services` from YAML
   - Call `Participant.add_service/2` for each service after participant creation

3. **Backward Compatibility**:
   - Participants without services field default to empty list `[]`
   - Existing participants can have services added via API

## Example YAML Structure

```yaml
participants:
  - id: seb
    name: SEB
    role: banking_partner
    services:
      - financing
      - payment_processing
      - escrow_services
      - settlement
    metadata:
      country: SE
      industry: Banking
    accounts:
      # ... existing accounts ...
```

## Benefits

1. **Service Discovery**: Find participants by capability
   ```elixir
   # Find all financing providers
   participants = Participant.list_participants()
   financing_providers = Enum.filter(participants, fn p -> 
     "financing" in (p.services || [])
   end)
   ```

2. **Dynamic Ecosystem**: Services can be added/removed without code changes

3. **Business Logic**: Use services to validate transactions
   ```elixir
   # Only allow financing from participants with "financing" service
   if "financing" in lender.services do
     create_loan(...)
   end
   ```

4. **Documentation**: Services serve as self-documenting capabilities

## Questions for Approval

1. Are these service names appropriate?
2. Should we add more granular services (e.g., `short_term_financing` vs `long_term_financing`)?
3. Should salons have services, or are they just consumers?
4. Do we need service categories/tags for grouping?

