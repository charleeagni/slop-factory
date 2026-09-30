# Historical X handle verification procedure

This document previously described CODING-2346 verification of automatic username registration. That procedure is superseded by the finished CODING-2359 specification, attachment `1d52f855-344e-4820-ba32-583da97aa40d`, dated 2026-09-29.

Use the [X username sharing rollout and rollback runbook](x-sharing-rollout-runbook.md) for CODING-2385. It targets only the owner-selected `https://toiylcfpbryztcfjievv.supabase.co`, requires backend readiness before client installation, and separates local evidence from blocked live checks.

The old procedure's handle-only RPC, durable username queue, launch replay and instruction to restore legacy RPC execution are invalid for this feature. The new flow requires a saved acknowledgement before account reads, memory-only activity that expires after 30 seconds, and a durable username-free withdrawal outbox. Rollback leaves withdrawal available and never restores legacy uploads.

The [historical report](x-handle-verification-report-2026-09-29.md) retains the prior results and their limits. Historical delivery acknowledgements were server upload receipts, not user consent. Old verification rows are neither backfilled into the new registry nor deleted by this ticket. A historical extraction check, upload result, or HTTP 502 probe cannot prove current live readiness. No release, post or DM is authorized by these documents.
