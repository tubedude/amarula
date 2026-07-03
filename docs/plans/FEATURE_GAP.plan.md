> **Historical design plan** — point-in-time; may not match current code. The living architecture reference is [docs/INFRASTRUCTURE.md](../INFRASTRUCTURE.md).

# Baileys feature gap — what Amarula does NOT implement

Audit of the Baileys socket public surface (`src/Socket/{socket,chats,messages-send,
messages-recv,groups}.ts`) against Amarula's public API (`lib/amarula.ex`) as of
2026-06-14. Not everything here is worth porting — this is a map, not a backlog.

## Implemented (for reference)
new/connect/disconnect/logout, connection_state, send_text/message/media/contact(s)/
location/poll, send_reaction/edit/revoke, set_presence, send_chatstate,
presence_subscribe, mark_read, group_metadata, list_groups. Receive side: messages,
receipts (delivery/read/played → :receipt_update), group changes (:group_update),
app-state **read** sync (chats/contacts), history sync, notifications
(w:gp2/server_sync/encrypt/account_sync/devices/picture), identity-change refresh.

## Gap 1 — Group MANAGEMENT (we can read, not act) ← BUILDING NOW
We expose group_metadata + list_groups (read) and receive :group_update, but cannot
make any change. Baileys group ops, none implemented:
- groupCreate, groupLeave
- groupParticipantsUpdate (add/remove/promote/demote)
- groupUpdateSubject, groupUpdateDescription
- groupSettingUpdate (announcement/not_announcement, locked/unlocked)
- groupToggleEphemeral (disappearing messages)
- groupInviteCode, groupRevokeInvite, groupGetInviteInfo, groupAcceptInvite
- groupMemberAddMode, groupJoinApprovalMode
- groupRequestParticipantsList, groupRequestParticipantsUpdate (join approvals)
All are `<iq to=<group> xmlns="w:g2">` builders + reply parsers — self-contained,
low protocol risk. High user value (the obvious asymmetry).

## Gap 2 — App-state WRITES (chatModify)
We decode incoming app-state patches (C2) but cannot SEND mutations. Baileys
`chatModify` covers archive / pin / mute / star / markRead / delete / clear. This is
the write-side counterpart to the C2 read stack (encode a SyncdPatch + LTHash, send
`w:sync:app:state` set). Deeper/more-interesting protocol work; the encode mirror of
what we already decode. MED-HIGH effort.

## Gap 3 — Profile / status / picture (setters, mostly trivial IQ)
profilePictureUrl, updateProfilePicture, removeProfilePicture, updateProfileName,
updateProfileStatus, fetchStatus, getBusinessProfile,
updateDefaultDisappearingMode, fetchDisappearingDuration. Individually small.

## Gap 4 — Privacy + blocklist
updateBlockStatus, fetchBlocklist, fetchPrivacySettings, and the update*Privacy
family (lastSeen/online/profilePicture/status/readReceipts/groupsAdd/messages/
callPrivacy/disableLinkPreviews). Niche; low priority.

## Gap 5 — Misc messaging
sendPeerDataOperationMessage (placeholder resend / history-on-demand),
updateMediaMessage (re-fetch expired media), createCallLink, label/quick-reply
ops (business). Low priority.

## Decision (2026-06-14)
Build **Gap 1 (group management)** now. The rest stays documented, not committed
to. Gap 2 (app-state writes) is the natural next deep dive if/when wanted.
Related: [[feature-surface-2026-06-14]], [[cm-split-plan]].
