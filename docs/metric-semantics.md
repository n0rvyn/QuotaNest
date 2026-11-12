# Ark metric contract

Verified against official AFP/seat API documentation, official Ark CLI contracts, and account-backed responses on 2026-11-12. No credentials or account identifiers are recorded here.

| Metric | Source and meaning | Display |
|---|---|---|
| Coding Plan used % | `QuotaUsage[].Percent`, percentage points, not a 0–1 fraction | Percentage and progress fill both mean **used** |
| Available % | `100 − usedPercent` | Explicit available label; menu bar selects the lowest available window |
| Coding Plan absolute quota | API provides percentage snapshot; `Cap` is not treated as a verified token allowance | No invented token/request total |
| Coding Plan reset | `ResetTimestamp`, Unix seconds; zero/negative means unavailable | Provider time, formatted in local timezone |
| Coding Plan source update | Observed `UpdateTimestamp` in Unix seconds; robust epoch conversion accepts seconds/milliseconds | Distinct from local fetch time |
| Agent Plan used and total | `AFPFiveHour` / `AFPDaily` / `AFPWeekly` / `AFPMonthly`: `Used` consumed AFP, `Quota` total AFP | Used / total AFP; available is total minus used |
| AFP reset | `ResetTime`, Unix milliseconds; zero/negative means unavailable | Provider time |
| AFP daily window | Applicable to certain media/Harness capabilities, not the same allowance as the text 5-hour window | Separate Daily row only when allowance is positive |
| No active AFP allowance | Empty PlanType and all quota fields zero in observed response | Not enabled, never fabricated as 100% available |
| Enabled model | `FoundationModelName` identity; `State == Available` | Only enabled models, across all pages |
| Model prices | `ChargeItems[].Price` and UnitCode | Not interpreted as quota consumption |
| Free inference allowance | `InferenceFreeUsage.Total` and `.Consumed` | Explicit consumed / total counter |
| Resource packs | `ResourcePackItems[].Type`, `.Consumed`, `.Total` | Separate free-inference and data-permission pack counters; no invented token units or reset |
| Team AFP response | `SeatAFPUsages[]`, matched by SeatID | Same AFP semantics as personal plan |
| Team discovery | `GetSeatInfo` with exactly one of SeatID or ProjectName; uses project default plus correct Scene | Empty entitlement differs from API failure |
| Error codes | Retain validated provider code punctuation, including `/` | A parameter or permission failure is not labeled disabled |

Progress bars fill with **used** quota. Available percentages remain explicit, so a nearly full allowance does not look nearly exhausted. Warning color depends on low available quota, independent of fill direction.

Primary sources:
- https://docs.volcengine.com/docs/ark/get-afp-usage-api?lang=zh
- https://docs.volcengine.com/docs/ark/get-seat-afp-usage-api?lang=zh
- https://github.com/volcengine/ark-cli/blob/main/skills/arkcli-usage/references/arkcli-usage-plan.md
- https://github.com/volcengine/ark-cli/blob/main/skills/arkcli-pricing/references/arkcli-pricing-models.md

## Corrected request and parsing defects
- Resource identity was incorrectly read from Name rather than FoundationModelName.
- Balances were incorrectly sought among price ChargeItems instead of InferenceFreeUsage and ResourcePackItems.
- Team AFP wrapper was incorrectly Items instead of SeatAFPUsages.
- Team discovery omitted ProjectName, producing InvalidParameter.SeatID/ProjectName.
- Error sanitization rejected the slash and replaced the provider's actionable code with UnknownError.
