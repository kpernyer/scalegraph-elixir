# Documentation Cleanup Analysis

## Summary

The `docs/` directory has **15 files**, many of which are stale, redundant, or could be consolidated. Here's what we found:

## Files to DELETE (Stale/Migration Complete)

These files document migrations or decisions that are already complete:

1. **`PROTO_SPLIT_MIGRATION.md`** - Migration guide for proto file split (✅ migration complete)
2. **`PROTO_SPLIT_RECOMMENDATION.md`** - Recommendation to split proto files (✅ decision made, split done)
3. **`PROTO_SPLIT_EXAMPLE.md`** - Example of how proto split would look (✅ split implemented)
4. **`PROTO_SYNC.md`** - Outdated! Says proto is a single file, but proto is now split into 4 files
5. **`ELIXIR_SERVER_UPDATE.md`** - Migration notes for updating Elixir server (✅ update complete)

**Action**: Delete all 5 files

## Files to CONSOLIDATE (Redundant with Root Docs)

These files duplicate information already in root markdown files:

6. **`ARCHITECTURE_SEPARATION.md`** - Layer separation details
   - **Redundant with**: `ARCHITECTURE.md` (which is more comprehensive)
   - **Action**: Delete - `ARCHITECTURE.md` already covers this thoroughly

7. **`LEDGER_DESIGN.md`** - Ledger design principles
   - **Redundant with**: `ARCHITECTURE.md` (Layer 1 section covers this)
   - **Action**: Delete - information is already in `ARCHITECTURE.md`

8. **`BUSINESS_TRANSACTIONS.md`** - Business transaction models
   - **Overlaps with**: `ARCHITECTURE.md` (Layer 2 section)
   - **Action**: Keep if it has unique details, otherwise delete
   - **Note**: Has some useful account type details, but most is covered in ARCHITECTURE.md

## Files to KEEP (Useful/Unique Content)

9. **`CLI-USER-GUIDE.md`** - ✅ Keep - Specific user guide for CLI tool
10. **`CONTRACT_YAML_GUIDE.md`** - ✅ Keep - Specific feature guide for YAML contracts
11. **`GENERIC_CONTRACTS.md`** - ✅ Keep - Specific feature guide for generic contracts
12. **`GIT_WORKFLOW.md`** - ✅ Keep - Useful workflow guide (could move to root, but fine in docs/)
13. **`MCP.md`** - ✅ Keep - Model Context Protocol documentation
14. **`SMART_CONTRACT_EXAMPLES.md`** - ✅ Keep - Examples are valuable
15. **`STRESS-TEST-RESULTS.md`** - ✅ Keep - Testing documentation
16. **`SUPPLIER_REGISTRATION_CONTRACT.md`** - ⚠️ Review - Referenced by SMART_CONTRACT_EXAMPLES.md
   - **Action**: Keep if it has more detail than the example in SMART_CONTRACT_EXAMPLES.md
   - Otherwise, consolidate into SMART_CONTRACT_EXAMPLES.md

## Recommended Actions

### Immediate Deletions (5 files)
```bash
rm docs/PROTO_SPLIT_MIGRATION.md
rm docs/PROTO_SPLIT_RECOMMENDATION.md
rm docs/PROTO_SPLIT_EXAMPLE.md
rm docs/PROTO_SYNC.md
rm docs/ELIXIR_SERVER_UPDATE.md
```

### Consolidation Deletions (2-3 files)
```bash
rm docs/ARCHITECTURE_SEPARATION.md
rm docs/LEDGER_DESIGN.md
# Optionally:
rm docs/BUSINESS_TRANSACTIONS.md  # If it doesn't have unique value
```

### Update README.md References

After cleanup, update `README.md` line 399-400 to remove references to deleted files:
- Remove `docs/ARCHITECTURE_SEPARATION.md` reference
- Remove `docs/LEDGER_DESIGN.md` reference

## Final Structure

After cleanup, `docs/` will have **7-8 focused files**:

1. `CLI-USER-GUIDE.md` - CLI usage
2. `CONTRACT_YAML_GUIDE.md` - YAML contracts
3. `GENERIC_CONTRACTS.md` - Generic contracts
4. `GIT_WORKFLOW.md` - Git workflow
5. `MCP.md` - MCP server docs
6. `SMART_CONTRACT_EXAMPLES.md` - Contract examples
7. `STRESS-TEST-RESULTS.md` - Test results
8. `SUPPLIER_REGISTRATION_CONTRACT.md` - (if kept)

## What's Already in Root Markdowns

The root markdown files already cover:
- **README.md**: Overview, quick start, architecture summary, features
- **ARCHITECTURE.md**: Comprehensive three-layer architecture, design decisions, examples
- **PROJECT.md**: Detailed component breakdown, data flow, domain model
- **CONVENTIONS.md**: Coding conventions
- **TASKS.md**: Task tracking

These root files are the primary documentation. The `docs/` directory should only contain:
- Feature-specific guides (CLI, MCP, YAML contracts)
- Examples and tutorials
- Testing documentation
- Workflow guides


