defmodule Amarula.Protocol.Proto.ADVEncryptionType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:E2EE, 0)
  field(:HOSTED, 1)
end

defmodule Amarula.Protocol.Proto.AIRichResponseMessageType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:AI_RICH_RESPONSE_TYPE_UNKNOWN, 0)
  field(:AI_RICH_RESPONSE_TYPE_STANDARD, 1)
end

defmodule Amarula.Protocol.Proto.AIRichResponseSubMessageType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:AI_RICH_RESPONSE_UNKNOWN, 0)
  field(:AI_RICH_RESPONSE_GRID_IMAGE, 1)
  field(:AI_RICH_RESPONSE_TEXT, 2)
  field(:AI_RICH_RESPONSE_INLINE_IMAGE, 3)
  field(:AI_RICH_RESPONSE_TABLE, 4)
  field(:AI_RICH_RESPONSE_CODE, 5)
  field(:AI_RICH_RESPONSE_DYNAMIC, 6)
  field(:AI_RICH_RESPONSE_MAP, 7)
  field(:AI_RICH_RESPONSE_LATEX, 8)
  field(:AI_RICH_RESPONSE_CONTENT_ITEMS, 9)
end

defmodule Amarula.Protocol.Proto.BotMetricsEntryPoint do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNDEFINED_ENTRY_POINT, 0)
  field(:FAVICON, 1)
  field(:CHATLIST, 2)
  field(:AISEARCH_NULL_STATE_PAPER_PLANE, 3)
  field(:AISEARCH_NULL_STATE_SUGGESTION, 4)
  field(:AISEARCH_TYPE_AHEAD_SUGGESTION, 5)
  field(:AISEARCH_TYPE_AHEAD_PAPER_PLANE, 6)
  field(:AISEARCH_TYPE_AHEAD_RESULT_CHATLIST, 7)
  field(:AISEARCH_TYPE_AHEAD_RESULT_MESSAGES, 8)
  field(:AIVOICE_SEARCH_BAR, 9)
  field(:AIVOICE_FAVICON, 10)
  field(:AISTUDIO, 11)
  field(:DEEPLINK, 12)
  field(:NOTIFICATION, 13)
  field(:PROFILE_MESSAGE_BUTTON, 14)
  field(:FORWARD, 15)
  field(:APP_SHORTCUT, 16)
  field(:FF_FAMILY, 17)
  field(:AI_TAB, 18)
  field(:AI_HOME, 19)
  field(:AI_DEEPLINK_IMMERSIVE, 20)
  field(:AI_DEEPLINK, 21)
  field(:META_AI_CHAT_SHORTCUT_AI_STUDIO, 22)
  field(:UGC_CHAT_SHORTCUT_AI_STUDIO, 23)
  field(:NEW_CHAT_AI_STUDIO, 24)
  field(:AIVOICE_FAVICON_CALL_HISTORY, 25)
  field(:ASK_META_AI_CONTEXT_MENU, 26)
  field(:ASK_META_AI_CONTEXT_MENU_1ON1, 27)
  field(:ASK_META_AI_CONTEXT_MENU_GROUP, 28)
  field(:INVOKE_META_AI_1ON1, 29)
  field(:INVOKE_META_AI_GROUP, 30)
  field(:META_AI_FORWARD, 31)
  field(:NEW_CHAT_AI_CONTACT, 32)
  field(:MESSAGE_QUICK_ACTION_1_ON_1_CHAT, 33)
  field(:MESSAGE_QUICK_ACTION_GROUP_CHAT, 34)
  field(:ATTACHMENT_TRAY_1_ON_1_CHAT, 35)
  field(:ATTACHMENT_TRAY_GROUP_CHAT, 36)
  field(:ASK_META_AI_MEDIA_VIEWER_1ON1, 37)
  field(:ASK_META_AI_MEDIA_VIEWER_GROUP, 38)
end

defmodule Amarula.Protocol.Proto.BotMetricsThreadEntryPoint do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_BOTMETRICSTHREADENTRYPOINT, 0)
  field(:AI_TAB_THREAD, 1)
  field(:AI_HOME_THREAD, 2)
  field(:AI_DEEPLINK_IMMERSIVE_THREAD, 3)
  field(:AI_DEEPLINK_THREAD, 4)
  field(:ASK_META_AI_CONTEXT_MENU_THREAD, 5)
end

defmodule Amarula.Protocol.Proto.BotSessionSource do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:NULL_STATE, 1)
  field(:TYPEAHEAD, 2)
  field(:USER_INPUT, 3)
  field(:EMU_FLASH, 4)
  field(:EMU_FLASH_FOLLOWUP, 5)
  field(:VOICE, 6)
end

defmodule Amarula.Protocol.Proto.CollectionName do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:COLLECTION_NAME_UNKNOWN, 0)
  field(:REGULAR, 1)
  field(:REGULAR_LOW, 2)
  field(:REGULAR_HIGH, 3)
  field(:CRITICAL_BLOCK, 4)
  field(:CRITICAL_UNBLOCK_LOW, 5)
end

defmodule Amarula.Protocol.Proto.KeepType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:KEEP_FOR_ALL, 1)
  field(:UNDO_KEEP_FOR_ALL, 2)
end

defmodule Amarula.Protocol.Proto.MediaVisibility do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:DEFAULT, 0)
  field(:OFF, 1)
  field(:ON, 2)
end

defmodule Amarula.Protocol.Proto.MutationProps do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_MUTATIONPROPS, 0)
  field(:STAR_ACTION, 2)
  field(:CONTACT_ACTION, 3)
  field(:MUTE_ACTION, 4)
  field(:PIN_ACTION, 5)
  field(:SECURITY_NOTIFICATION_SETTING, 6)
  field(:PUSH_NAME_SETTING, 7)
  field(:QUICK_REPLY_ACTION, 8)
  field(:RECENT_EMOJI_WEIGHTS_ACTION, 11)
  field(:LABEL_MESSAGE_ACTION, 13)
  field(:LABEL_EDIT_ACTION, 14)
  field(:LABEL_ASSOCIATION_ACTION, 15)
  field(:LOCALE_SETTING, 16)
  field(:ARCHIVE_CHAT_ACTION, 17)
  field(:DELETE_MESSAGE_FOR_ME_ACTION, 18)
  field(:KEY_EXPIRATION, 19)
  field(:MARK_CHAT_AS_READ_ACTION, 20)
  field(:CLEAR_CHAT_ACTION, 21)
  field(:DELETE_CHAT_ACTION, 22)
  field(:UNARCHIVE_CHATS_SETTING, 23)
  field(:PRIMARY_FEATURE, 24)
  field(:ANDROID_UNSUPPORTED_ACTIONS, 26)
  field(:AGENT_ACTION, 27)
  field(:SUBSCRIPTION_ACTION, 28)
  field(:USER_STATUS_MUTE_ACTION, 29)
  field(:TIME_FORMAT_ACTION, 30)
  field(:NUX_ACTION, 31)
  field(:PRIMARY_VERSION_ACTION, 32)
  field(:STICKER_ACTION, 33)
  field(:REMOVE_RECENT_STICKER_ACTION, 34)
  field(:CHAT_ASSIGNMENT, 35)
  field(:CHAT_ASSIGNMENT_OPENED_STATUS, 36)
  field(:PN_FOR_LID_CHAT_ACTION, 37)
  field(:MARKETING_MESSAGE_ACTION, 38)
  field(:MARKETING_MESSAGE_BROADCAST_ACTION, 39)
  field(:EXTERNAL_WEB_BETA_ACTION, 40)
  field(:PRIVACY_SETTING_RELAY_ALL_CALLS, 41)
  field(:CALL_LOG_ACTION, 42)
  field(:UGC_BOT, 43)
  field(:STATUS_PRIVACY, 44)
  field(:BOT_WELCOME_REQUEST_ACTION, 45)
  field(:DELETE_INDIVIDUAL_CALL_LOG, 46)
  field(:LABEL_REORDERING_ACTION, 47)
  field(:PAYMENT_INFO_ACTION, 48)
  field(:CUSTOM_PAYMENT_METHODS_ACTION, 49)
  field(:LOCK_CHAT_ACTION, 50)
  field(:CHAT_LOCK_SETTINGS, 51)
  field(:WAMO_USER_IDENTIFIER_ACTION, 52)
  field(:PRIVACY_SETTING_DISABLE_LINK_PREVIEWS_ACTION, 53)
  field(:DEVICE_CAPABILITIES, 54)
  field(:NOTE_EDIT_ACTION, 55)
  field(:FAVORITES_ACTION, 56)
  field(:MERCHANT_PAYMENT_PARTNER_ACTION, 57)
  field(:WAFFLE_ACCOUNT_LINK_STATE_ACTION, 58)
  field(:USERNAME_CHAT_START_MODE, 59)
  field(:NOTIFICATION_ACTIVITY_SETTING_ACTION, 60)
  field(:LID_CONTACT_ACTION, 61)
  field(:CTWA_PER_CUSTOMER_DATA_SHARING_ACTION, 62)
  field(:PAYMENT_TOS_ACTION, 63)
  field(:PRIVACY_SETTING_CHANNELS_PERSONALISED_RECOMMENDATION_ACTION, 64)
  field(:BUSINESS_BROADCAST_ASSOCIATION_ACTION, 65)
  field(:DETECTED_OUTCOMES_STATUS_ACTION, 66)
  field(:MAIBA_AI_FEATURES_CONTROL_ACTION, 68)
  field(:BUSINESS_BROADCAST_LIST_ACTION, 69)
  field(:MUSIC_USER_ID_ACTION, 70)
  field(:STATUS_POST_OPT_IN_NOTIFICATION_PREFERENCES_ACTION, 71)
  field(:AVATAR_UPDATED_ACTION, 72)
  field(:GALAXY_FLOW_ACTION, 73)
  field(:PRIVATE_PROCESSING_SETTING_ACTION, 74)
  field(:NEWSLETTER_SAVED_INTERESTS_ACTION, 75)
  field(:AI_THREAD_RENAME_ACTION, 76)
  field(:INTERACTIVE_MESSAGE_ACTION, 77)
  field(:SHARE_OWN_PN, 10001)
  field(:BUSINESS_BROADCAST_ACTION, 10002)
end

defmodule Amarula.Protocol.Proto.PrivacySystemMessage do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_PRIVACYSYSTEMMESSAGE, 0)
  field(:E2EE_MSG, 1)
  field(:NE2EE_SELF, 2)
  field(:NE2EE_OTHER, 3)
end

defmodule Amarula.Protocol.Proto.SessionTransparencyType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_TYPE, 0)
  field(:NY_AI_SAFETY_DISCLAIMER, 1)
end

defmodule Amarula.Protocol.Proto.WebLinkRenderConfig do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:WEBVIEW, 0)
  field(:SYSTEM, 1)
end

defmodule Amarula.Protocol.Proto.AIHomeState.AIHomeOption.AIHomeActionType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:PROMPT, 0)
  field(:CREATE_IMAGE, 1)
  field(:ANIMATE_PHOTO, 2)
  field(:ANALYZE_FILE, 3)
end

defmodule Amarula.Protocol.Proto.AIRichResponseCodeMetadata.AIRichResponseCodeHighlightType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:AI_RICH_RESPONSE_CODE_HIGHLIGHT_DEFAULT, 0)
  field(:AI_RICH_RESPONSE_CODE_HIGHLIGHT_KEYWORD, 1)
  field(:AI_RICH_RESPONSE_CODE_HIGHLIGHT_METHOD, 2)
  field(:AI_RICH_RESPONSE_CODE_HIGHLIGHT_STRING, 3)
  field(:AI_RICH_RESPONSE_CODE_HIGHLIGHT_NUMBER, 4)
  field(:AI_RICH_RESPONSE_CODE_HIGHLIGHT_COMMENT, 5)
end

defmodule Amarula.Protocol.Proto.AIRichResponseContentItemsMetadata.ContentType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:DEFAULT, 0)
  field(:CAROUSEL, 1)
end

defmodule Amarula.Protocol.Proto.AIRichResponseDynamicMetadata.AIRichResponseDynamicMetadataType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:AI_RICH_RESPONSE_DYNAMIC_METADATA_TYPE_UNKNOWN, 0)
  field(:AI_RICH_RESPONSE_DYNAMIC_METADATA_TYPE_IMAGE, 1)
  field(:AI_RICH_RESPONSE_DYNAMIC_METADATA_TYPE_GIF, 2)
end

defmodule Amarula.Protocol.Proto.AIRichResponseInlineImageMetadata.AIRichResponseImageAlignment do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:AI_RICH_RESPONSE_IMAGE_LAYOUT_LEADING_ALIGNED, 0)
  field(:AI_RICH_RESPONSE_IMAGE_LAYOUT_TRAILING_ALIGNED, 1)
  field(:AI_RICH_RESPONSE_IMAGE_LAYOUT_CENTER_ALIGNED, 2)
end

defmodule Amarula.Protocol.Proto.AIThreadInfo.AIThreadClientInfo.AIThreadType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:DEFAULT, 1)
  field(:INCOGNITO, 2)
end

defmodule Amarula.Protocol.Proto.BizAccountLinkInfo.AccountType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ENTERPRISE, 0)
end

defmodule Amarula.Protocol.Proto.BizAccountLinkInfo.HostStorageType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ON_PREMISE, 0)
  field(:FACEBOOK, 1)
end

defmodule Amarula.Protocol.Proto.BizIdentityInfo.ActualActorsType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:SELF, 0)
  field(:BSP, 1)
end

defmodule Amarula.Protocol.Proto.BizIdentityInfo.HostStorageType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ON_PREMISE, 0)
  field(:FACEBOOK, 1)
end

defmodule Amarula.Protocol.Proto.BizIdentityInfo.VerifiedLevelValue do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:LOW, 1)
  field(:HIGH, 2)
end

defmodule Amarula.Protocol.Proto.BotAgeCollectionMetadata.AgeCollectionType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:O18_BINARY, 0)
  field(:WAFFLE, 1)
end

defmodule Amarula.Protocol.Proto.BotCapabilityMetadata.BotCapabilityType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:PROGRESS_INDICATOR, 1)
  field(:RICH_RESPONSE_HEADING, 2)
  field(:RICH_RESPONSE_NESTED_LIST, 3)
  field(:AI_MEMORY, 4)
  field(:RICH_RESPONSE_THREAD_SURFING, 5)
  field(:RICH_RESPONSE_TABLE, 6)
  field(:RICH_RESPONSE_CODE, 7)
  field(:RICH_RESPONSE_STRUCTURED_RESPONSE, 8)
  field(:RICH_RESPONSE_INLINE_IMAGE, 9)
  field(:WA_IG_1P_PLUGIN_RANKING_CONTROL, 10)
  field(:WA_IG_1P_PLUGIN_RANKING_UPDATE_1, 11)
  field(:WA_IG_1P_PLUGIN_RANKING_UPDATE_2, 12)
  field(:WA_IG_1P_PLUGIN_RANKING_UPDATE_3, 13)
  field(:WA_IG_1P_PLUGIN_RANKING_UPDATE_4, 14)
  field(:WA_IG_1P_PLUGIN_RANKING_UPDATE_5, 15)
  field(:WA_IG_1P_PLUGIN_RANKING_UPDATE_6, 16)
  field(:WA_IG_1P_PLUGIN_RANKING_UPDATE_7, 17)
  field(:WA_IG_1P_PLUGIN_RANKING_UPDATE_8, 18)
  field(:WA_IG_1P_PLUGIN_RANKING_UPDATE_9, 19)
  field(:WA_IG_1P_PLUGIN_RANKING_UPDATE_10, 20)
  field(:RICH_RESPONSE_SUB_HEADING, 21)
  field(:RICH_RESPONSE_GRID_IMAGE, 22)
  field(:AI_STUDIO_UGC_MEMORY, 23)
  field(:RICH_RESPONSE_LATEX, 24)
  field(:RICH_RESPONSE_MAPS, 25)
  field(:RICH_RESPONSE_INLINE_REELS, 26)
  field(:AGENTIC_PLANNING, 27)
  field(:ACCOUNT_LINKING, 28)
  field(:STREAMING_DISAGGREGATION, 29)
  field(:RICH_RESPONSE_GRID_IMAGE_3P, 30)
  field(:RICH_RESPONSE_LATEX_INLINE, 31)
  field(:QUERY_PLAN, 32)
  field(:PROACTIVE_MESSAGE, 33)
  field(:RICH_RESPONSE_UNIFIED_RESPONSE, 34)
  field(:PROMOTION_MESSAGE, 35)
  field(:SIMPLIFIED_PROFILE_PAGE, 36)
  field(:RICH_RESPONSE_SOURCES_IN_MESSAGE, 37)
  field(:RICH_RESPONSE_SIDE_BY_SIDE_SURVEY, 38)
  field(:RICH_RESPONSE_UNIFIED_TEXT_COMPONENT, 39)
  field(:AI_SHARED_MEMORY, 40)
  field(:RICH_RESPONSE_UNIFIED_SOURCES, 41)
  field(:RICH_RESPONSE_UNIFIED_DOMAIN_CITATIONS, 42)
  field(:RICH_RESPONSE_UR_INLINE_REELS_ENABLED, 43)
  field(:RICH_RESPONSE_UR_MEDIA_GRID_ENABLED, 44)
  field(:RICH_RESPONSE_UR_TIMESTAMP_PLACEHOLDER, 45)
  field(:RICH_RESPONSE_IN_APP_SURVEY, 46)
  field(:AI_RESPONSE_MODEL_BRANDING, 47)
  field(:SESSION_TRANSPARENCY_SYSTEM_MESSAGE, 48)
  field(:RICH_RESPONSE_UR_REASONING, 49)
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.BotFeedbackKind do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:BOT_FEEDBACK_POSITIVE, 0)
  field(:BOT_FEEDBACK_NEGATIVE_GENERIC, 1)
  field(:BOT_FEEDBACK_NEGATIVE_HELPFUL, 2)
  field(:BOT_FEEDBACK_NEGATIVE_INTERESTING, 3)
  field(:BOT_FEEDBACK_NEGATIVE_ACCURATE, 4)
  field(:BOT_FEEDBACK_NEGATIVE_SAFE, 5)
  field(:BOT_FEEDBACK_NEGATIVE_OTHER, 6)
  field(:BOT_FEEDBACK_NEGATIVE_REFUSED, 7)
  field(:BOT_FEEDBACK_NEGATIVE_NOT_VISUALLY_APPEALING, 8)
  field(:BOT_FEEDBACK_NEGATIVE_NOT_RELEVANT_TO_TEXT, 9)
  field(:BOT_FEEDBACK_NEGATIVE_PERSONALIZED, 10)
  field(:BOT_FEEDBACK_NEGATIVE_CLARITY, 11)
  field(:BOT_FEEDBACK_NEGATIVE_DOESNT_LOOK_LIKE_THE_PERSON, 12)
  field(:BOT_FEEDBACK_NEGATIVE_HALLUCINATION_INTERNAL_ONLY, 13)
  field(:BOT_FEEDBACK_NEGATIVE, 14)
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.BotFeedbackKindMultipleNegative do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_BOTFEEDBACKKINDMULTIPLENEGATIVE, 0)
  field(:BOT_FEEDBACK_MULTIPLE_NEGATIVE_GENERIC, 1)
  field(:BOT_FEEDBACK_MULTIPLE_NEGATIVE_HELPFUL, 2)
  field(:BOT_FEEDBACK_MULTIPLE_NEGATIVE_INTERESTING, 4)
  field(:BOT_FEEDBACK_MULTIPLE_NEGATIVE_ACCURATE, 8)
  field(:BOT_FEEDBACK_MULTIPLE_NEGATIVE_SAFE, 16)
  field(:BOT_FEEDBACK_MULTIPLE_NEGATIVE_OTHER, 32)
  field(:BOT_FEEDBACK_MULTIPLE_NEGATIVE_REFUSED, 64)
  field(:BOT_FEEDBACK_MULTIPLE_NEGATIVE_NOT_VISUALLY_APPEALING, 128)
  field(:BOT_FEEDBACK_MULTIPLE_NEGATIVE_NOT_RELEVANT_TO_TEXT, 256)
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.BotFeedbackKindMultiplePositive do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_BOTFEEDBACKKINDMULTIPLEPOSITIVE, 0)
  field(:BOT_FEEDBACK_MULTIPLE_POSITIVE_GENERIC, 1)
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.ReportKind do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:GENERIC, 1)
end

defmodule Amarula.Protocol.Proto.BotImagineMetadata.ImagineType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:IMAGINE, 1)
  field(:MEMU, 2)
  field(:FLASH, 3)
  field(:EDIT, 4)
end

defmodule Amarula.Protocol.Proto.BotLinkedAccount.BotLinkedAccountType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:BOT_LINKED_ACCOUNT_TYPE_1P, 0)
end

defmodule Amarula.Protocol.Proto.BotMediaMetadata.OrientationType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_ORIENTATIONTYPE, 0)
  field(:CENTER, 1)
  field(:LEFT, 2)
  field(:RIGHT, 3)
end

defmodule Amarula.Protocol.Proto.BotMessageOrigin.BotMessageOriginType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:BOT_MESSAGE_ORIGIN_TYPE_AI_INITIATED, 0)
end

defmodule Amarula.Protocol.Proto.BotModeSelectionMetadata.BotUserSelectionMode do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_MODE, 0)
  field(:REASONING_MODE, 1)
end

defmodule Amarula.Protocol.Proto.BotModelMetadata.ModelType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_TYPE, 0)
  field(:LLAMA_PROD, 1)
  field(:LLAMA_PROD_PREMIUM, 2)
end

defmodule Amarula.Protocol.Proto.BotModelMetadata.PremiumModelStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_STATUS, 0)
  field(:AVAILABLE, 1)
  field(:QUOTA_EXCEED_LIMIT, 2)
end

defmodule Amarula.Protocol.Proto.BotPluginMetadata.PluginType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_PLUGIN, 0)
  field(:REELS, 1)
  field(:SEARCH, 2)
end

defmodule Amarula.Protocol.Proto.BotPluginMetadata.SearchProvider do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:BING, 1)
  field(:GOOGLE, 2)
  field(:SUPPORT, 3)
end

defmodule Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.BotSearchSourceProvider do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_PROVIDER, 0)
  field(:OTHER, 1)
  field(:GOOGLE, 2)
  field(:BING, 3)
end

defmodule Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.PlanningStepStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:PLANNED, 1)
  field(:EXECUTING, 2)
  field(:FINISHED, 3)
end

defmodule Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.BotPlanningSearchSourcesMetadata.BotPlanningSearchSourceProvider do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:OTHER, 1)
  field(:GOOGLE, 2)
  field(:BING, 3)
end

defmodule Amarula.Protocol.Proto.BotPromotionMessageMetadata.BotPromotionType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_TYPE, 0)
  field(:C50, 1)
  field(:SURVEY_PLATFORM, 2)
end

defmodule Amarula.Protocol.Proto.BotQuotaMetadata.BotFeatureQuotaMetadata.BotFeatureType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_FEATURE, 0)
  field(:REASONING_FEATURE, 1)
end

defmodule Amarula.Protocol.Proto.BotReminderMetadata.ReminderAction do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_REMINDERACTION, 0)
  field(:NOTIFY, 1)
  field(:CREATE, 2)
  field(:DELETE, 3)
  field(:UPDATE, 4)
end

defmodule Amarula.Protocol.Proto.BotReminderMetadata.ReminderFrequency do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_REMINDERFREQUENCY, 0)
  field(:ONCE, 1)
  field(:DAILY, 2)
  field(:WEEKLY, 3)
  field(:BIWEEKLY, 4)
  field(:MONTHLY, 5)
end

defmodule Amarula.Protocol.Proto.BotSignatureVerificationUseCaseProof.BotSignatureUseCase do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNSPECIFIED, 0)
  field(:WA_BOT_MSG, 1)
end

defmodule Amarula.Protocol.Proto.BotSourcesMetadata.BotSourceItem.SourceProvider do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:BING, 1)
  field(:GOOGLE, 2)
  field(:SUPPORT, 3)
  field(:OTHER, 4)
end

defmodule Amarula.Protocol.Proto.CallLogRecord.CallResult do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:CONNECTED, 0)
  field(:REJECTED, 1)
  field(:CANCELLED, 2)
  field(:ACCEPTEDELSEWHERE, 3)
  field(:MISSED, 4)
  field(:INVALID, 5)
  field(:UNAVAILABLE, 6)
  field(:UPCOMING, 7)
  field(:FAILED, 8)
  field(:ABANDONED, 9)
  field(:ONGOING, 10)
end

defmodule Amarula.Protocol.Proto.CallLogRecord.CallType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:REGULAR, 0)
  field(:SCHEDULED_CALL, 1)
  field(:VOICE_CHAT, 2)
end

defmodule Amarula.Protocol.Proto.CallLogRecord.SilenceReason do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:SCHEDULED, 1)
  field(:PRIVACY, 2)
  field(:LIGHTWEIGHT, 3)
end

defmodule Amarula.Protocol.Proto.ChatRowOpaqueData.DraftMessage.CtwaContextData.ContextInfoExternalAdReplyInfoMediaType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:IMAGE, 1)
  field(:VIDEO, 2)
end

defmodule Amarula.Protocol.Proto.ClientPayload.AccountType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:DEFAULT, 0)
  field(:GUEST, 1)
end

defmodule Amarula.Protocol.Proto.ClientPayload.ConnectReason do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:PUSH, 0)
  field(:USER_ACTIVATED, 1)
  field(:SCHEDULED, 2)
  field(:ERROR_RECONNECT, 3)
  field(:NETWORK_SWITCH, 4)
  field(:PING_RECONNECT, 5)
  field(:UNKNOWN, 6)
end

defmodule Amarula.Protocol.Proto.ClientPayload.ConnectType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:CELLULAR_UNKNOWN, 0)
  field(:WIFI_UNKNOWN, 1)
  field(:CELLULAR_EDGE, 100)
  field(:CELLULAR_IDEN, 101)
  field(:CELLULAR_UMTS, 102)
  field(:CELLULAR_EVDO, 103)
  field(:CELLULAR_GPRS, 104)
  field(:CELLULAR_HSDPA, 105)
  field(:CELLULAR_HSUPA, 106)
  field(:CELLULAR_HSPA, 107)
  field(:CELLULAR_CDMA, 108)
  field(:CELLULAR_1XRTT, 109)
  field(:CELLULAR_EHRPD, 110)
  field(:CELLULAR_LTE, 111)
  field(:CELLULAR_HSPAP, 112)
end

defmodule Amarula.Protocol.Proto.ClientPayload.IOSAppExtension do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:SHARE_EXTENSION, 0)
  field(:SERVICE_EXTENSION, 1)
  field(:INTENTS_EXTENSION, 2)
end

defmodule Amarula.Protocol.Proto.ClientPayload.Product do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:WHATSAPP, 0)
  field(:MESSENGER, 1)
  field(:INTEROP, 2)
  field(:INTEROP_MSGR, 3)
  field(:WHATSAPP_LID, 4)
end

defmodule Amarula.Protocol.Proto.ClientPayload.TrafficAnonymization do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:OFF, 0)
  field(:STANDARD, 1)
end

defmodule Amarula.Protocol.Proto.ClientPayload.DNSSource.DNSResolutionMethod do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:SYSTEM, 0)
  field(:GOOGLE, 1)
  field(:HARDCODED, 2)
  field(:OVERRIDE, 3)
  field(:FALLBACK, 4)
  field(:MNS, 5)
end

defmodule Amarula.Protocol.Proto.ClientPayload.UserAgent.DeviceType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:PHONE, 0)
  field(:TABLET, 1)
  field(:DESKTOP, 2)
  field(:WEARABLE, 3)
  field(:VR, 4)
end

defmodule Amarula.Protocol.Proto.ClientPayload.UserAgent.Platform do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ANDROID, 0)
  field(:IOS, 1)
  field(:WINDOWS_PHONE, 2)
  field(:BLACKBERRY, 3)
  field(:BLACKBERRYX, 4)
  field(:S40, 5)
  field(:S60, 6)
  field(:PYTHON_CLIENT, 7)
  field(:TIZEN, 8)
  field(:ENTERPRISE, 9)
  field(:SMB_ANDROID, 10)
  field(:KAIOS, 11)
  field(:SMB_IOS, 12)
  field(:WINDOWS, 13)
  field(:WEB, 14)
  field(:PORTAL, 15)
  field(:GREEN_ANDROID, 16)
  field(:GREEN_IPHONE, 17)
  field(:BLUE_ANDROID, 18)
  field(:BLUE_IPHONE, 19)
  field(:FBLITE_ANDROID, 20)
  field(:MLITE_ANDROID, 21)
  field(:IGLITE_ANDROID, 22)
  field(:PAGE, 23)
  field(:MACOS, 24)
  field(:OCULUS_MSG, 25)
  field(:OCULUS_CALL, 26)
  field(:MILAN, 27)
  field(:CAPI, 28)
  field(:WEAROS, 29)
  field(:ARDEVICE, 30)
  field(:VRDEVICE, 31)
  field(:BLUE_WEB, 32)
  field(:IPAD, 33)
  field(:TEST, 34)
  field(:SMART_GLASSES, 35)
  field(:BLUE_VR, 36)
  field(:AR_WRIST, 37)
end

defmodule Amarula.Protocol.Proto.ClientPayload.UserAgent.ReleaseChannel do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:RELEASE, 0)
  field(:BETA, 1)
  field(:ALPHA, 2)
  field(:DEBUG, 3)
end

defmodule Amarula.Protocol.Proto.ClientPayload.WebInfo.WebSubPlatform do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:WEB_BROWSER, 0)
  field(:APP_STORE, 1)
  field(:WIN_STORE, 2)
  field(:DARWIN, 3)
  field(:WIN32, 4)
  field(:WIN_HYBRID, 5)
end

defmodule Amarula.Protocol.Proto.ContextInfo.ForwardOrigin do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:CHAT, 1)
  field(:STATUS, 2)
  field(:CHANNELS, 3)
  field(:META_AI, 4)
  field(:UGC, 5)
end

defmodule Amarula.Protocol.Proto.ContextInfo.PairedMediaType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NOT_PAIRED_MEDIA, 0)
  field(:SD_VIDEO_PARENT, 1)
  field(:HD_VIDEO_CHILD, 2)
  field(:SD_IMAGE_PARENT, 3)
  field(:HD_IMAGE_CHILD, 4)
  field(:MOTION_PHOTO_PARENT, 5)
  field(:MOTION_PHOTO_CHILD, 6)
  field(:HEVC_VIDEO_PARENT, 7)
  field(:HEVC_VIDEO_CHILD, 8)
end

defmodule Amarula.Protocol.Proto.ContextInfo.QuotedType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:EXPLICIT, 0)
  field(:AUTO, 1)
end

defmodule Amarula.Protocol.Proto.ContextInfo.StatusAttributionType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:RESHARED_FROM_MENTION, 1)
  field(:RESHARED_FROM_POST, 2)
  field(:RESHARED_FROM_POST_MANY_TIMES, 3)
  field(:FORWARDED_FROM_STATUS, 4)
end

defmodule Amarula.Protocol.Proto.ContextInfo.StatusSourceType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:IMAGE, 0)
  field(:VIDEO, 1)
  field(:GIF, 2)
  field(:AUDIO, 3)
  field(:TEXT, 4)
  field(:MUSIC_STANDALONE, 5)
end

defmodule Amarula.Protocol.Proto.ContextInfo.AdReplyInfo.MediaType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:IMAGE, 1)
  field(:VIDEO, 2)
end

defmodule Amarula.Protocol.Proto.ContextInfo.DataSharingContext.DataSharingFlags do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_DATASHARINGFLAGS, 0)
  field(:SHOW_MM_DISCLOSURE_ON_CLICK, 1)
  field(:SHOW_MM_DISCLOSURE_ON_READ, 2)
end

defmodule Amarula.Protocol.Proto.ContextInfo.ExternalAdReplyInfo.AdType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:CTWA, 0)
  field(:CAWC, 1)
end

defmodule Amarula.Protocol.Proto.ContextInfo.ExternalAdReplyInfo.MediaType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:IMAGE, 1)
  field(:VIDEO, 2)
end

defmodule Amarula.Protocol.Proto.ContextInfo.ForwardedNewsletterMessageInfo.ContentType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_CONTENTTYPE, 0)
  field(:UPDATE, 1)
  field(:UPDATE_CARD, 2)
  field(:LINK_CARD, 3)
end

defmodule Amarula.Protocol.Proto.ContextInfo.StatusAudienceMetadata.AudienceType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:CLOSE_FRIENDS, 1)
end

defmodule Amarula.Protocol.Proto.Conversation.EndOfHistoryTransferType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:COMPLETE_BUT_MORE_MESSAGES_REMAIN_ON_PRIMARY, 0)
  field(:COMPLETE_AND_NO_MORE_MESSAGE_REMAIN_ON_PRIMARY, 1)
  field(:COMPLETE_ON_DEMAND_SYNC_BUT_MORE_MSG_REMAIN_ON_PRIMARY, 2)
end

defmodule Amarula.Protocol.Proto.DeviceCapabilities.ChatLockSupportLevel do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:MINIMAL, 1)
  field(:FULL, 2)
end

defmodule Amarula.Protocol.Proto.DeviceCapabilities.MemberNameTagPrimarySupport do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:DISABLED, 0)
  field(:RECEIVER_ENABLED, 1)
  field(:SENDER_ENABLED, 2)
end

defmodule Amarula.Protocol.Proto.DeviceProps.PlatformType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:CHROME, 1)
  field(:FIREFOX, 2)
  field(:IE, 3)
  field(:OPERA, 4)
  field(:SAFARI, 5)
  field(:EDGE, 6)
  field(:DESKTOP, 7)
  field(:IPAD, 8)
  field(:ANDROID_TABLET, 9)
  field(:OHANA, 10)
  field(:ALOHA, 11)
  field(:CATALINA, 12)
  field(:TCL_TV, 13)
  field(:IOS_PHONE, 14)
  field(:IOS_CATALYST, 15)
  field(:ANDROID_PHONE, 16)
  field(:ANDROID_AMBIGUOUS, 17)
  field(:WEAR_OS, 18)
  field(:AR_WRIST, 19)
  field(:AR_DEVICE, 20)
  field(:UWP, 21)
  field(:VR, 22)
  field(:CLOUD_API, 23)
  field(:SMARTGLASSES, 24)
end

defmodule Amarula.Protocol.Proto.DisappearingMode.Initiator do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:CHANGED_IN_CHAT, 0)
  field(:INITIATED_BY_ME, 1)
  field(:INITIATED_BY_OTHER, 2)
  field(:BIZ_UPGRADE_FB_HOSTING, 3)
end

defmodule Amarula.Protocol.Proto.DisappearingMode.Trigger do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:CHAT_SETTING, 1)
  field(:ACCOUNT_SETTING, 2)
  field(:BULK_CHANGE, 3)
  field(:BIZ_SUPPORTS_FB_HOSTING, 4)
  field(:UNKNOWN_GROUPS, 5)
end

defmodule Amarula.Protocol.Proto.GroupHistoryBundleInfo.ProcessState do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NOT_INJECTED, 0)
  field(:INJECTED, 1)
  field(:INJECTED_PARTIAL, 2)
  field(:INJECTION_FAILED, 3)
  field(:INJECTION_FAILED_NO_RETRY, 4)
end

defmodule Amarula.Protocol.Proto.GroupParticipant.Rank do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:REGULAR, 0)
  field(:ADMIN, 1)
  field(:SUPERADMIN, 2)
end

defmodule Amarula.Protocol.Proto.HistorySync.BotAIWaitListState do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:IN_WAITLIST, 0)
  field(:AI_AVAILABLE, 1)
end

defmodule Amarula.Protocol.Proto.HistorySync.HistorySyncType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:INITIAL_BOOTSTRAP, 0)
  field(:INITIAL_STATUS_V3, 1)
  field(:FULL, 2)
  field(:RECENT, 3)
  field(:PUSH_NAME, 4)
  field(:NON_BLOCKING_DATA, 5)
  field(:ON_DEMAND, 6)
end

defmodule Amarula.Protocol.Proto.HydratedTemplateButton.HydratedURLButton.WebviewPresentationType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_WEBVIEWPRESENTATIONTYPE, 0)
  field(:FULL, 1)
  field(:TALL, 2)
  field(:COMPACT, 3)
end

defmodule Amarula.Protocol.Proto.InteractiveAnnotation.StatusLinkType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_STATUSLINKTYPE, 0)
  field(:RASTERIZED_LINK_PREVIEW, 1)
  field(:RASTERIZED_LINK_TRUNCATED, 2)
  field(:RASTERIZED_LINK_FULL_URL, 3)
end

defmodule Amarula.Protocol.Proto.LimitSharing.TriggerType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:CHAT_SETTING, 1)
  field(:BIZ_SUPPORTS_FB_HOSTING, 2)
  field(:UNKNOWN_GROUP, 3)
end

defmodule Amarula.Protocol.Proto.MediaRetryNotification.ResultType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:GENERAL_ERROR, 0)
  field(:SUCCESS, 1)
  field(:NOT_FOUND, 2)
  field(:DECRYPTION_ERROR, 3)
end

defmodule Amarula.Protocol.Proto.Message.HistorySyncType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:INITIAL_BOOTSTRAP, 0)
  field(:INITIAL_STATUS_V3, 1)
  field(:FULL, 2)
  field(:RECENT, 3)
  field(:PUSH_NAME, 4)
  field(:NON_BLOCKING_DATA, 5)
  field(:ON_DEMAND, 6)
  field(:NO_HISTORY, 7)
  field(:MESSAGE_ACCESS_STATUS, 8)
end

defmodule Amarula.Protocol.Proto.Message.MediaKeyDomain do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNSET, 0)
  field(:E2EE_CHAT, 1)
  field(:STATUS, 2)
  field(:CAPI, 3)
  field(:BOT, 4)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UPLOAD_STICKER, 0)
  field(:SEND_RECENT_STICKER_BOOTSTRAP, 1)
  field(:GENERATE_LINK_PREVIEW, 2)
  field(:HISTORY_SYNC_ON_DEMAND, 3)
  field(:PLACEHOLDER_MESSAGE_RESEND, 4)
  field(:WAFFLE_LINKING_NONCE_FETCH, 5)
  field(:FULL_HISTORY_SYNC_ON_DEMAND, 6)
  field(:COMPANION_META_NONCE_FETCH, 7)
  field(:COMPANION_SYNCD_SNAPSHOT_FATAL_RECOVERY, 8)
  field(:COMPANION_CANONICAL_USER_NONCE_FETCH, 9)
  field(:HISTORY_SYNC_CHUNK_RETRY, 10)
  field(:GALAXY_FLOW_ACTION, 11)
end

defmodule Amarula.Protocol.Proto.Message.PollContentType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:TEXT, 1)
  field(:IMAGE, 2)
end

defmodule Amarula.Protocol.Proto.Message.PollType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:POLL, 0)
  field(:QUIZ, 1)
end

defmodule Amarula.Protocol.Proto.Message.BCallMessage.MediaType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:AUDIO, 1)
  field(:VIDEO, 2)
end

defmodule Amarula.Protocol.Proto.Message.ButtonsMessage.HeaderType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:EMPTY, 1)
  field(:TEXT, 2)
  field(:DOCUMENT, 3)
  field(:IMAGE, 4)
  field(:VIDEO, 5)
  field(:LOCATION, 6)
end

defmodule Amarula.Protocol.Proto.Message.ButtonsMessage.Button.Type do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:RESPONSE, 1)
  field(:NATIVE_FLOW, 2)
end

defmodule Amarula.Protocol.Proto.Message.ButtonsResponseMessage.Type do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:DISPLAY_TEXT, 1)
end

defmodule Amarula.Protocol.Proto.Message.CallLogMessage.CallOutcome do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:CONNECTED, 0)
  field(:MISSED, 1)
  field(:FAILED, 2)
  field(:REJECTED, 3)
  field(:ACCEPTED_ELSEWHERE, 4)
  field(:ONGOING, 5)
  field(:SILENCED_BY_DND, 6)
  field(:SILENCED_UNKNOWN_CALLER, 7)
end

defmodule Amarula.Protocol.Proto.Message.CallLogMessage.CallType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:REGULAR, 0)
  field(:SCHEDULED_CALL, 1)
  field(:VOICE_CHAT, 2)
end

defmodule Amarula.Protocol.Proto.Message.CloudAPIThreadControlNotification.CloudAPIThreadControl do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:CONTROL_PASSED, 1)
  field(:CONTROL_TAKEN, 2)
end

defmodule Amarula.Protocol.Proto.Message.EventResponseMessage.EventResponseType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:GOING, 1)
  field(:NOT_GOING, 2)
  field(:MAYBE, 3)
end

defmodule Amarula.Protocol.Proto.Message.ExtendedTextMessage.FontType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:SYSTEM, 0)
  field(:SYSTEM_TEXT, 1)
  field(:FB_SCRIPT, 2)
  field(:SYSTEM_BOLD, 6)
  field(:MORNINGBREEZE_REGULAR, 7)
  field(:CALISTOGA_REGULAR, 8)
  field(:EXO2_EXTRABOLD, 9)
  field(:COURIERPRIME_BOLD, 10)
end

defmodule Amarula.Protocol.Proto.Message.ExtendedTextMessage.InviteLinkGroupType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:DEFAULT, 0)
  field(:PARENT, 1)
  field(:SUB, 2)
  field(:DEFAULT_SUB, 3)
end

defmodule Amarula.Protocol.Proto.Message.ExtendedTextMessage.PreviewType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:VIDEO, 1)
  field(:PLACEHOLDER, 4)
  field(:IMAGE, 5)
  field(:PAYMENT_LINKS, 6)
  field(:PROFILE, 7)
end

defmodule Amarula.Protocol.Proto.Message.GroupInviteMessage.GroupType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:DEFAULT, 0)
  field(:PARENT, 1)
end

defmodule Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeComponent.CalendarType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_CALENDARTYPE, 0)
  field(:GREGORIAN, 1)
  field(:SOLAR_HIJRI, 2)
end

defmodule Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeComponent.DayOfWeekType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_DAYOFWEEKTYPE, 0)
  field(:MONDAY, 1)
  field(:TUESDAY, 2)
  field(:WEDNESDAY, 3)
  field(:THURSDAY, 4)
  field(:FRIDAY, 5)
  field(:SATURDAY, 6)
  field(:SUNDAY, 7)
end

defmodule Amarula.Protocol.Proto.Message.ImageMessage.ImageSourceType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:USER_IMAGE, 0)
  field(:AI_GENERATED, 1)
  field(:AI_MODIFIED, 2)
  field(:RASTERIZED_TEXT_STATUS, 3)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage.CarouselMessage.CarouselCardType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:HSCROLL_CARDS, 1)
  field(:ALBUM_IMAGE, 2)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage.ShopMessage.Surface do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_SURFACE, 0)
  field(:FB, 1)
  field(:IG, 2)
  field(:WA, 3)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveResponseMessage.Body.Format do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:DEFAULT, 0)
  field(:EXTENSIONS_1, 1)
end

defmodule Amarula.Protocol.Proto.Message.InvoiceMessage.AttachmentType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:IMAGE, 0)
  field(:PDF, 1)
end

defmodule Amarula.Protocol.Proto.Message.LinkPreviewMetadata.SocialMediaPostType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:REEL, 1)
  field(:LIVE_VIDEO, 2)
  field(:LONG_VIDEO, 3)
  field(:SINGLE_IMAGE, 4)
  field(:CAROUSEL, 5)
end

defmodule Amarula.Protocol.Proto.Message.ListMessage.ListType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:SINGLE_SELECT, 1)
  field(:PRODUCT_LIST, 2)
end

defmodule Amarula.Protocol.Proto.Message.ListResponseMessage.ListType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:SINGLE_SELECT, 1)
end

defmodule Amarula.Protocol.Proto.Message.OrderMessage.OrderStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_ORDERSTATUS, 0)
  field(:INQUIRY, 1)
  field(:ACCEPTED, 2)
  field(:DECLINED, 3)
end

defmodule Amarula.Protocol.Proto.Message.OrderMessage.OrderSurface do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_ORDERSURFACE, 0)
  field(:CATALOG, 1)
end

defmodule Amarula.Protocol.Proto.Message.PaymentInviteMessage.ServiceType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:FBPAY, 1)
  field(:NOVI, 2)
  field(:UPI, 3)
end

defmodule Amarula.Protocol.Proto.Message.PaymentLinkMetadata.PaymentLinkHeader.PaymentLinkHeaderType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:LINK_PREVIEW, 0)
  field(:ORDER, 1)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.GalaxyFlowAction.GalaxyFlowActionType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_GALAXYFLOWACTIONTYPE, 0)
  field(:NOTIFY_LAUNCH, 1)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.FullHistorySyncOnDemandResponseCode do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:REQUEST_SUCCESS, 0)
  field(:REQUEST_TIME_EXPIRED, 1)
  field(:DECLINED_SHARING_HISTORY, 2)
  field(:GENERIC_ERROR, 3)
  field(:ERROR_REQUEST_ON_NON_SMB_PRIMARY, 4)
  field(:ERROR_HOSTED_DEVICE_NOT_CONNECTED, 5)
  field(:ERROR_HOSTED_DEVICE_LOGIN_TIME_NOT_SET, 6)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.HistorySyncChunkRetryResponseCode do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_HISTORYSYNCCHUNKRETRYRESPONSECODE, 0)
  field(:GENERATION_ERROR, 1)
  field(:CHUNK_CONSUMED, 2)
  field(:TIMEOUT, 3)
  field(:SESSION_EXHAUSTED, 4)
  field(:CHUNK_EXHAUSTED, 5)
  field(:DUPLICATED_REQUEST, 6)
end

defmodule Amarula.Protocol.Proto.Message.PinInChatMessage.Type do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_TYPE, 0)
  field(:PIN_FOR_ALL, 1)
  field(:UNPIN_FOR_ALL, 2)
end

defmodule Amarula.Protocol.Proto.Message.PlaceholderMessage.PlaceholderType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:MASK_LINKED_DEVICES, 0)
end

defmodule Amarula.Protocol.Proto.Message.ProtocolMessage.Type do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:REVOKE, 0)
  field(:EPHEMERAL_SETTING, 3)
  field(:EPHEMERAL_SYNC_RESPONSE, 4)
  field(:HISTORY_SYNC_NOTIFICATION, 5)
  field(:APP_STATE_SYNC_KEY_SHARE, 6)
  field(:APP_STATE_SYNC_KEY_REQUEST, 7)
  field(:MSG_FANOUT_BACKFILL_REQUEST, 8)
  field(:INITIAL_SECURITY_NOTIFICATION_SETTING_SYNC, 9)
  field(:APP_STATE_FATAL_EXCEPTION_NOTIFICATION, 10)
  field(:SHARE_PHONE_NUMBER, 11)
  field(:MESSAGE_EDIT, 14)
  field(:PEER_DATA_OPERATION_REQUEST_MESSAGE, 16)
  field(:PEER_DATA_OPERATION_REQUEST_RESPONSE_MESSAGE, 17)
  field(:REQUEST_WELCOME_MESSAGE, 18)
  field(:BOT_FEEDBACK_MESSAGE, 19)
  field(:MEDIA_NOTIFY_MESSAGE, 20)
  field(:CLOUD_API_THREAD_CONTROL_NOTIFICATION, 21)
  field(:LID_MIGRATION_MAPPING_SYNC, 22)
  field(:REMINDER_MESSAGE, 23)
  field(:BOT_MEMU_ONBOARDING_MESSAGE, 24)
  field(:STATUS_MENTION_MESSAGE, 25)
  field(:STOP_GENERATION_MESSAGE, 26)
  field(:LIMIT_SHARING, 27)
  field(:AI_PSI_METADATA, 28)
  field(:AI_QUERY_FANOUT, 29)
  field(:GROUP_MEMBER_LABEL_CHANGE, 30)
end

defmodule Amarula.Protocol.Proto.Message.RequestWelcomeMessageMetadata.LocalChatState do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:EMPTY, 0)
  field(:NON_EMPTY, 1)
end

defmodule Amarula.Protocol.Proto.Message.ScheduledCallCreationMessage.CallType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:VOICE, 1)
  field(:VIDEO, 2)
end

defmodule Amarula.Protocol.Proto.Message.ScheduledCallEditMessage.EditType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:CANCEL, 1)
end

defmodule Amarula.Protocol.Proto.Message.SecretEncryptedMessage.SecretEncType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:EVENT_EDIT, 1)
  field(:MESSAGE_EDIT, 2)
end

defmodule Amarula.Protocol.Proto.Message.StatusNotificationMessage.StatusNotificationType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:STATUS_ADD_YOURS, 1)
  field(:STATUS_RESHARE, 2)
  field(:STATUS_QUESTION_ANSWER_RESHARE, 3)
end

defmodule Amarula.Protocol.Proto.Message.StatusQuotedMessage.StatusQuotedMessageType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_STATUSQUOTEDMESSAGETYPE, 0)
  field(:QUESTION_ANSWER, 1)
end

defmodule Amarula.Protocol.Proto.Message.StatusStickerInteractionMessage.StatusStickerType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:REACTION, 1)
end

defmodule Amarula.Protocol.Proto.Message.StickerPackMessage.StickerPackOrigin do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:FIRST_PARTY, 0)
  field(:THIRD_PARTY, 1)
  field(:USER_CREATED, 2)
end

defmodule Amarula.Protocol.Proto.Message.VideoMessage.Attribution do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:GIPHY, 1)
  field(:TENOR, 2)
  field(:KLIPY, 3)
end

defmodule Amarula.Protocol.Proto.Message.VideoMessage.VideoSourceType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:USER_VIDEO, 0)
  field(:AI_GENERATED, 1)
end

defmodule Amarula.Protocol.Proto.MessageAddOn.MessageAddOnType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNDEFINED, 0)
  field(:REACTION, 1)
  field(:EVENT_RESPONSE, 2)
  field(:POLL_UPDATE, 3)
  field(:PIN_IN_CHAT, 4)
end

defmodule Amarula.Protocol.Proto.MessageAssociation.AssociationType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:MEDIA_ALBUM, 1)
  field(:BOT_PLUGIN, 2)
  field(:EVENT_COVER_IMAGE, 3)
  field(:STATUS_POLL, 4)
  field(:HD_VIDEO_DUAL_UPLOAD, 5)
  field(:STATUS_EXTERNAL_RESHARE, 6)
  field(:MEDIA_POLL, 7)
  field(:STATUS_ADD_YOURS, 8)
  field(:STATUS_NOTIFICATION, 9)
  field(:HD_IMAGE_DUAL_UPLOAD, 10)
  field(:STICKER_ANNOTATION, 11)
  field(:MOTION_PHOTO, 12)
  field(:STATUS_LINK_ACTION, 13)
  field(:VIEW_ALL_REPLIES, 14)
  field(:STATUS_ADD_YOURS_AI_IMAGINE, 15)
  field(:STATUS_QUESTION, 16)
  field(:STATUS_ADD_YOURS_DIWALI, 17)
  field(:STATUS_REACTION, 18)
  field(:HEVC_VIDEO_DUAL_UPLOAD, 19)
end

defmodule Amarula.Protocol.Proto.MessageContextInfo.MessageAddonExpiryType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_MESSAGEADDONEXPIRYTYPE, 0)
  field(:STATIC, 1)
  field(:DEPENDENT_ON_PARENT, 2)
end

defmodule Amarula.Protocol.Proto.MsgOpaqueData.PollContentType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:TEXT, 1)
  field(:IMAGE, 2)
end

defmodule Amarula.Protocol.Proto.MsgOpaqueData.PollType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:POLL, 0)
  field(:QUIZ, 1)
end

defmodule Amarula.Protocol.Proto.PastParticipant.LeaveReason do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:LEFT, 0)
  field(:REMOVED, 1)
end

defmodule Amarula.Protocol.Proto.PatchDebugData.Platform do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ANDROID, 0)
  field(:SMBA, 1)
  field(:IPHONE, 2)
  field(:SMBI, 3)
  field(:WEB, 4)
  field(:UWP, 5)
  field(:DARWIN, 6)
  field(:IPAD, 7)
  field(:WEAROS, 8)
  field(:WASG, 9)
  field(:WEARM, 10)
  field(:CAPI, 11)
end

defmodule Amarula.Protocol.Proto.PaymentBackground.Type do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:DEFAULT, 1)
end

defmodule Amarula.Protocol.Proto.PaymentInfo.Currency do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_CURRENCY, 0)
  field(:INR, 1)
end

defmodule Amarula.Protocol.Proto.PaymentInfo.Status do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_STATUS, 0)
  field(:PROCESSING, 1)
  field(:SENT, 2)
  field(:NEED_TO_ACCEPT, 3)
  field(:COMPLETE, 4)
  field(:COULD_NOT_COMPLETE, 5)
  field(:REFUNDED, 6)
  field(:EXPIRED, 7)
  field(:REJECTED, 8)
  field(:CANCELLED, 9)
  field(:WAITING_FOR_PAYER, 10)
  field(:WAITING, 11)
end

defmodule Amarula.Protocol.Proto.PaymentInfo.TxnStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:PENDING_SETUP, 1)
  field(:PENDING_RECEIVER_SETUP, 2)
  field(:INIT, 3)
  field(:SUCCESS, 4)
  field(:COMPLETED, 5)
  field(:FAILED, 6)
  field(:FAILED_RISK, 7)
  field(:FAILED_PROCESSING, 8)
  field(:FAILED_RECEIVER_PROCESSING, 9)
  field(:FAILED_DA, 10)
  field(:FAILED_DA_FINAL, 11)
  field(:REFUNDED_TXN, 12)
  field(:REFUND_FAILED, 13)
  field(:REFUND_FAILED_PROCESSING, 14)
  field(:REFUND_FAILED_DA, 15)
  field(:EXPIRED_TXN, 16)
  field(:AUTH_CANCELED, 17)
  field(:AUTH_CANCEL_FAILED_PROCESSING, 18)
  field(:AUTH_CANCEL_FAILED, 19)
  field(:COLLECT_INIT, 20)
  field(:COLLECT_SUCCESS, 21)
  field(:COLLECT_FAILED, 22)
  field(:COLLECT_FAILED_RISK, 23)
  field(:COLLECT_REJECTED, 24)
  field(:COLLECT_EXPIRED, 25)
  field(:COLLECT_CANCELED, 26)
  field(:COLLECT_CANCELLING, 27)
  field(:IN_REVIEW, 28)
  field(:REVERSAL_SUCCESS, 29)
  field(:REVERSAL_PENDING, 30)
  field(:REFUND_PENDING, 31)
end

defmodule Amarula.Protocol.Proto.PinInChat.Type do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_TYPE, 0)
  field(:PIN_FOR_ALL, 1)
  field(:UNPIN_FOR_ALL, 2)
end

defmodule Amarula.Protocol.Proto.ProcessedVideo.VideoQuality do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNDEFINED, 0)
  field(:LOW, 1)
  field(:MID, 2)
  field(:HIGH, 3)
end

defmodule Amarula.Protocol.Proto.StatusAttribution.Type do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:RESHARE, 1)
  field(:EXTERNAL_SHARE, 2)
  field(:MUSIC, 3)
  field(:STATUS_MENTION, 4)
  field(:GROUP_STATUS, 5)
  field(:RL_ATTRIBUTION, 6)
  field(:AI_CREATED, 7)
  field(:LAYOUTS, 8)
end

defmodule Amarula.Protocol.Proto.StatusAttribution.AiCreatedAttribution.Source do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:STATUS_MIMICRY, 1)
end

defmodule Amarula.Protocol.Proto.StatusAttribution.ExternalShare.Source do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:INSTAGRAM, 1)
  field(:FACEBOOK, 2)
  field(:MESSENGER, 3)
  field(:SPOTIFY, 4)
  field(:YOUTUBE, 5)
  field(:PINTEREST, 6)
  field(:THREADS, 7)
  field(:APPLE_MUSIC, 8)
  field(:SHARECHAT, 9)
  field(:GOOGLE_PHOTOS, 10)
end

defmodule Amarula.Protocol.Proto.StatusAttribution.RLAttribution.Source do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:RAY_BAN_META_GLASSES, 1)
  field(:OAKLEY_META_GLASSES, 2)
  field(:HYPERNOVA_GLASSES, 3)
end

defmodule Amarula.Protocol.Proto.StatusAttribution.StatusReshare.Source do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:INTERNAL_RESHARE, 1)
  field(:MENTION_RESHARE, 2)
  field(:CHANNEL_RESHARE, 3)
  field(:FORWARD, 4)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.AvatarUpdatedAction.AvatarEventType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UPDATED, 0)
  field(:CREATED, 1)
  field(:DELETED, 2)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.InteractiveMessageAction.InteractiveMessageActionMode do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_INTERACTIVEMESSAGEACTIONMODE, 0)
  field(:DISABLE_CTA, 1)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.LabelEditAction.ListType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:UNREAD, 1)
  field(:GROUPS, 2)
  field(:FAVORITES, 3)
  field(:PREDEFINED, 4)
  field(:CUSTOM, 5)
  field(:COMMUNITY, 6)
  field(:SERVER_ASSIGNED, 7)
  field(:DRAFTED, 8)
  field(:AI_HANDOFF, 9)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MaibaAIFeaturesControlAction.MaibaAIFeatureStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ENABLED, 0)
  field(:ENABLED_HAS_LEARNING, 1)
  field(:DISABLED, 2)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MarketingMessageAction.MarketingMessagePrototypeType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:PERSONALIZED, 0)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MerchantPaymentPartnerAction.Status do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ACTIVE, 0)
  field(:INACTIVE, 1)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.NoteEditAction.NoteType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_NOTETYPE, 0)
  field(:UNSTRUCTURED, 1)
  field(:STRUCTURED, 2)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.NotificationActivitySettingAction.NotificationActivitySetting do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:DEFAULT_ALL_MESSAGES, 0)
  field(:ALL_MESSAGES, 1)
  field(:HIGHLIGHTS, 2)
  field(:DEFAULT_HIGHLIGHTS, 3)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PaymentTosAction.PaymentNotice do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:BR_PAY_PRIVACY_POLICY, 0)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PrivateProcessingSettingAction.PrivateProcessingStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNDEFINED, 0)
  field(:ENABLED, 1)
  field(:DISABLED, 2)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.StatusPrivacyAction.StatusDistributionMode do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ALLOW_LIST, 0)
  field(:DENY_LIST, 1)
  field(:CONTACTS, 2)
  field(:CLOSE_FRIENDS, 3)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.UsernameChatStartModeAction.ChatStartMode do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN_CHATSTARTMODE, 0)
  field(:LID, 1)
  field(:PN, 2)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.WaffleAccountLinkStateAction.AccountLinkState do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ACTIVE, 0)
  field(:PAUSED, 1)
  field(:UNLINKED, 2)
end

defmodule Amarula.Protocol.Proto.SyncdMutation.SyncdOperation do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:SET, 0)
  field(:REMOVE, 1)
end

defmodule Amarula.Protocol.Proto.ThreadID.ThreadType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:VIEW_REPLIES, 1)
  field(:AI_THREAD, 2)
end

defmodule Amarula.Protocol.Proto.UserPassword.Encoding do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UTF8, 0)
  field(:UTF8_BROKEN, 1)
end

defmodule Amarula.Protocol.Proto.UserPassword.Transformer do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NONE, 0)
  field(:PBKDF2_HMAC_SHA512, 1)
  field(:PBKDF2_HMAC_SHA384, 2)
end

defmodule Amarula.Protocol.Proto.WebFeatures.Flag do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:NOT_STARTED, 0)
  field(:FORCE_UPGRADE, 1)
  field(:DEVELOPMENT, 2)
  field(:PRODUCTION, 3)
end

defmodule Amarula.Protocol.Proto.WebMessageInfo.BizPrivacyStatus do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:E2EE, 0)
  field(:FB, 2)
  field(:BSP, 1)
  field(:BSP_AND_FB, 3)
end

defmodule Amarula.Protocol.Proto.WebMessageInfo.Status do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ERROR, 0)
  field(:PENDING, 1)
  field(:SERVER_ACK, 2)
  field(:DELIVERY_ACK, 3)
  field(:READ, 4)
  field(:PLAYED, 5)
end

defmodule Amarula.Protocol.Proto.WebMessageInfo.StubType do
  @moduledoc false

  use Protobuf, enum: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:UNKNOWN, 0)
  field(:REVOKE, 1)
  field(:CIPHERTEXT, 2)
  field(:FUTUREPROOF, 3)
  field(:NON_VERIFIED_TRANSITION, 4)
  field(:UNVERIFIED_TRANSITION, 5)
  field(:VERIFIED_TRANSITION, 6)
  field(:VERIFIED_LOW_UNKNOWN, 7)
  field(:VERIFIED_HIGH, 8)
  field(:VERIFIED_INITIAL_UNKNOWN, 9)
  field(:VERIFIED_INITIAL_LOW, 10)
  field(:VERIFIED_INITIAL_HIGH, 11)
  field(:VERIFIED_TRANSITION_ANY_TO_NONE, 12)
  field(:VERIFIED_TRANSITION_ANY_TO_HIGH, 13)
  field(:VERIFIED_TRANSITION_HIGH_TO_LOW, 14)
  field(:VERIFIED_TRANSITION_HIGH_TO_UNKNOWN, 15)
  field(:VERIFIED_TRANSITION_UNKNOWN_TO_LOW, 16)
  field(:VERIFIED_TRANSITION_LOW_TO_UNKNOWN, 17)
  field(:VERIFIED_TRANSITION_NONE_TO_LOW, 18)
  field(:VERIFIED_TRANSITION_NONE_TO_UNKNOWN, 19)
  field(:GROUP_CREATE, 20)
  field(:GROUP_CHANGE_SUBJECT, 21)
  field(:GROUP_CHANGE_ICON, 22)
  field(:GROUP_CHANGE_INVITE_LINK, 23)
  field(:GROUP_CHANGE_DESCRIPTION, 24)
  field(:GROUP_CHANGE_RESTRICT, 25)
  field(:GROUP_CHANGE_ANNOUNCE, 26)
  field(:GROUP_PARTICIPANT_ADD, 27)
  field(:GROUP_PARTICIPANT_REMOVE, 28)
  field(:GROUP_PARTICIPANT_PROMOTE, 29)
  field(:GROUP_PARTICIPANT_DEMOTE, 30)
  field(:GROUP_PARTICIPANT_INVITE, 31)
  field(:GROUP_PARTICIPANT_LEAVE, 32)
  field(:GROUP_PARTICIPANT_CHANGE_NUMBER, 33)
  field(:BROADCAST_CREATE, 34)
  field(:BROADCAST_ADD, 35)
  field(:BROADCAST_REMOVE, 36)
  field(:GENERIC_NOTIFICATION, 37)
  field(:E2E_IDENTITY_CHANGED, 38)
  field(:E2E_ENCRYPTED, 39)
  field(:CALL_MISSED_VOICE, 40)
  field(:CALL_MISSED_VIDEO, 41)
  field(:INDIVIDUAL_CHANGE_NUMBER, 42)
  field(:GROUP_DELETE, 43)
  field(:GROUP_ANNOUNCE_MODE_MESSAGE_BOUNCE, 44)
  field(:CALL_MISSED_GROUP_VOICE, 45)
  field(:CALL_MISSED_GROUP_VIDEO, 46)
  field(:PAYMENT_CIPHERTEXT, 47)
  field(:PAYMENT_FUTUREPROOF, 48)
  field(:PAYMENT_TRANSACTION_STATUS_UPDATE_FAILED, 49)
  field(:PAYMENT_TRANSACTION_STATUS_UPDATE_REFUNDED, 50)
  field(:PAYMENT_TRANSACTION_STATUS_UPDATE_REFUND_FAILED, 51)
  field(:PAYMENT_TRANSACTION_STATUS_RECEIVER_PENDING_SETUP, 52)
  field(:PAYMENT_TRANSACTION_STATUS_RECEIVER_SUCCESS_AFTER_HICCUP, 53)
  field(:PAYMENT_ACTION_ACCOUNT_SETUP_REMINDER, 54)
  field(:PAYMENT_ACTION_SEND_PAYMENT_REMINDER, 55)
  field(:PAYMENT_ACTION_SEND_PAYMENT_INVITATION, 56)
  field(:PAYMENT_ACTION_REQUEST_DECLINED, 57)
  field(:PAYMENT_ACTION_REQUEST_EXPIRED, 58)
  field(:PAYMENT_ACTION_REQUEST_CANCELLED, 59)
  field(:BIZ_VERIFIED_TRANSITION_TOP_TO_BOTTOM, 60)
  field(:BIZ_VERIFIED_TRANSITION_BOTTOM_TO_TOP, 61)
  field(:BIZ_INTRO_TOP, 62)
  field(:BIZ_INTRO_BOTTOM, 63)
  field(:BIZ_NAME_CHANGE, 64)
  field(:BIZ_MOVE_TO_CONSUMER_APP, 65)
  field(:BIZ_TWO_TIER_MIGRATION_TOP, 66)
  field(:BIZ_TWO_TIER_MIGRATION_BOTTOM, 67)
  field(:OVERSIZED, 68)
  field(:GROUP_CHANGE_NO_FREQUENTLY_FORWARDED, 69)
  field(:GROUP_V4_ADD_INVITE_SENT, 70)
  field(:GROUP_PARTICIPANT_ADD_REQUEST_JOIN, 71)
  field(:CHANGE_EPHEMERAL_SETTING, 72)
  field(:E2E_DEVICE_CHANGED, 73)
  field(:VIEWED_ONCE, 74)
  field(:E2E_ENCRYPTED_NOW, 75)
  field(:BLUE_MSG_BSP_FB_TO_BSP_PREMISE, 76)
  field(:BLUE_MSG_BSP_FB_TO_SELF_FB, 77)
  field(:BLUE_MSG_BSP_FB_TO_SELF_PREMISE, 78)
  field(:BLUE_MSG_BSP_FB_UNVERIFIED, 79)
  field(:BLUE_MSG_BSP_FB_UNVERIFIED_TO_SELF_PREMISE_VERIFIED, 80)
  field(:BLUE_MSG_BSP_FB_VERIFIED, 81)
  field(:BLUE_MSG_BSP_FB_VERIFIED_TO_SELF_PREMISE_UNVERIFIED, 82)
  field(:BLUE_MSG_BSP_PREMISE_TO_SELF_PREMISE, 83)
  field(:BLUE_MSG_BSP_PREMISE_UNVERIFIED, 84)
  field(:BLUE_MSG_BSP_PREMISE_UNVERIFIED_TO_SELF_PREMISE_VERIFIED, 85)
  field(:BLUE_MSG_BSP_PREMISE_VERIFIED, 86)
  field(:BLUE_MSG_BSP_PREMISE_VERIFIED_TO_SELF_PREMISE_UNVERIFIED, 87)
  field(:BLUE_MSG_CONSUMER_TO_BSP_FB_UNVERIFIED, 88)
  field(:BLUE_MSG_CONSUMER_TO_BSP_PREMISE_UNVERIFIED, 89)
  field(:BLUE_MSG_CONSUMER_TO_SELF_FB_UNVERIFIED, 90)
  field(:BLUE_MSG_CONSUMER_TO_SELF_PREMISE_UNVERIFIED, 91)
  field(:BLUE_MSG_SELF_FB_TO_BSP_PREMISE, 92)
  field(:BLUE_MSG_SELF_FB_TO_SELF_PREMISE, 93)
  field(:BLUE_MSG_SELF_FB_UNVERIFIED, 94)
  field(:BLUE_MSG_SELF_FB_UNVERIFIED_TO_SELF_PREMISE_VERIFIED, 95)
  field(:BLUE_MSG_SELF_FB_VERIFIED, 96)
  field(:BLUE_MSG_SELF_FB_VERIFIED_TO_SELF_PREMISE_UNVERIFIED, 97)
  field(:BLUE_MSG_SELF_PREMISE_TO_BSP_PREMISE, 98)
  field(:BLUE_MSG_SELF_PREMISE_UNVERIFIED, 99)
  field(:BLUE_MSG_SELF_PREMISE_VERIFIED, 100)
  field(:BLUE_MSG_TO_BSP_FB, 101)
  field(:BLUE_MSG_TO_CONSUMER, 102)
  field(:BLUE_MSG_TO_SELF_FB, 103)
  field(:BLUE_MSG_UNVERIFIED_TO_BSP_FB_VERIFIED, 104)
  field(:BLUE_MSG_UNVERIFIED_TO_BSP_PREMISE_VERIFIED, 105)
  field(:BLUE_MSG_UNVERIFIED_TO_SELF_FB_VERIFIED, 106)
  field(:BLUE_MSG_UNVERIFIED_TO_VERIFIED, 107)
  field(:BLUE_MSG_VERIFIED_TO_BSP_FB_UNVERIFIED, 108)
  field(:BLUE_MSG_VERIFIED_TO_BSP_PREMISE_UNVERIFIED, 109)
  field(:BLUE_MSG_VERIFIED_TO_SELF_FB_UNVERIFIED, 110)
  field(:BLUE_MSG_VERIFIED_TO_UNVERIFIED, 111)
  field(:BLUE_MSG_BSP_FB_UNVERIFIED_TO_BSP_PREMISE_VERIFIED, 112)
  field(:BLUE_MSG_BSP_FB_UNVERIFIED_TO_SELF_FB_VERIFIED, 113)
  field(:BLUE_MSG_BSP_FB_VERIFIED_TO_BSP_PREMISE_UNVERIFIED, 114)
  field(:BLUE_MSG_BSP_FB_VERIFIED_TO_SELF_FB_UNVERIFIED, 115)
  field(:BLUE_MSG_SELF_FB_UNVERIFIED_TO_BSP_PREMISE_VERIFIED, 116)
  field(:BLUE_MSG_SELF_FB_VERIFIED_TO_BSP_PREMISE_UNVERIFIED, 117)
  field(:E2E_IDENTITY_UNAVAILABLE, 118)
  field(:GROUP_CREATING, 119)
  field(:GROUP_CREATE_FAILED, 120)
  field(:GROUP_BOUNCED, 121)
  field(:BLOCK_CONTACT, 122)
  field(:EPHEMERAL_SETTING_NOT_APPLIED, 123)
  field(:SYNC_FAILED, 124)
  field(:SYNCING, 125)
  field(:BIZ_PRIVACY_MODE_INIT_FB, 126)
  field(:BIZ_PRIVACY_MODE_INIT_BSP, 127)
  field(:BIZ_PRIVACY_MODE_TO_FB, 128)
  field(:BIZ_PRIVACY_MODE_TO_BSP, 129)
  field(:DISAPPEARING_MODE, 130)
  field(:E2E_DEVICE_FETCH_FAILED, 131)
  field(:ADMIN_REVOKE, 132)
  field(:GROUP_INVITE_LINK_GROWTH_LOCKED, 133)
  field(:COMMUNITY_LINK_PARENT_GROUP, 134)
  field(:COMMUNITY_LINK_SIBLING_GROUP, 135)
  field(:COMMUNITY_LINK_SUB_GROUP, 136)
  field(:COMMUNITY_UNLINK_PARENT_GROUP, 137)
  field(:COMMUNITY_UNLINK_SIBLING_GROUP, 138)
  field(:COMMUNITY_UNLINK_SUB_GROUP, 139)
  field(:GROUP_PARTICIPANT_ACCEPT, 140)
  field(:GROUP_PARTICIPANT_LINKED_GROUP_JOIN, 141)
  field(:COMMUNITY_CREATE, 142)
  field(:EPHEMERAL_KEEP_IN_CHAT, 143)
  field(:GROUP_MEMBERSHIP_JOIN_APPROVAL_REQUEST, 144)
  field(:GROUP_MEMBERSHIP_JOIN_APPROVAL_MODE, 145)
  field(:INTEGRITY_UNLINK_PARENT_GROUP, 146)
  field(:COMMUNITY_PARTICIPANT_PROMOTE, 147)
  field(:COMMUNITY_PARTICIPANT_DEMOTE, 148)
  field(:COMMUNITY_PARENT_GROUP_DELETED, 149)
  field(:COMMUNITY_LINK_PARENT_GROUP_MEMBERSHIP_APPROVAL, 150)
  field(:GROUP_PARTICIPANT_JOINED_GROUP_AND_PARENT_GROUP, 151)
  field(:MASKED_THREAD_CREATED, 152)
  field(:MASKED_THREAD_UNMASKED, 153)
  field(:BIZ_CHAT_ASSIGNMENT, 154)
  field(:CHAT_PSA, 155)
  field(:CHAT_POLL_CREATION_MESSAGE, 156)
  field(:CAG_MASKED_THREAD_CREATED, 157)
  field(:COMMUNITY_PARENT_GROUP_SUBJECT_CHANGED, 158)
  field(:CAG_INVITE_AUTO_ADD, 159)
  field(:BIZ_CHAT_ASSIGNMENT_UNASSIGN, 160)
  field(:CAG_INVITE_AUTO_JOINED, 161)
  field(:SCHEDULED_CALL_START_MESSAGE, 162)
  field(:COMMUNITY_INVITE_RICH, 163)
  field(:COMMUNITY_INVITE_AUTO_ADD_RICH, 164)
  field(:SUB_GROUP_INVITE_RICH, 165)
  field(:SUB_GROUP_PARTICIPANT_ADD_RICH, 166)
  field(:COMMUNITY_LINK_PARENT_GROUP_RICH, 167)
  field(:COMMUNITY_PARTICIPANT_ADD_RICH, 168)
  field(:SILENCED_UNKNOWN_CALLER_AUDIO, 169)
  field(:SILENCED_UNKNOWN_CALLER_VIDEO, 170)
  field(:GROUP_MEMBER_ADD_MODE, 171)
  field(:GROUP_MEMBERSHIP_JOIN_APPROVAL_REQUEST_NON_ADMIN_ADD, 172)
  field(:COMMUNITY_CHANGE_DESCRIPTION, 173)
  field(:SENDER_INVITE, 174)
  field(:RECEIVER_INVITE, 175)
  field(:COMMUNITY_ALLOW_MEMBER_ADDED_GROUPS, 176)
  field(:PINNED_MESSAGE_IN_CHAT, 177)
  field(:PAYMENT_INVITE_SETUP_INVITER, 178)
  field(:PAYMENT_INVITE_SETUP_INVITEE_RECEIVE_ONLY, 179)
  field(:PAYMENT_INVITE_SETUP_INVITEE_SEND_AND_RECEIVE, 180)
  field(:LINKED_GROUP_CALL_START, 181)
  field(:REPORT_TO_ADMIN_ENABLED_STATUS, 182)
  field(:EMPTY_SUBGROUP_CREATE, 183)
  field(:SCHEDULED_CALL_CANCEL, 184)
  field(:SUBGROUP_ADMIN_TRIGGERED_AUTO_ADD_RICH, 185)
  field(:GROUP_CHANGE_RECENT_HISTORY_SHARING, 186)
  field(:PAID_MESSAGE_SERVER_CAMPAIGN_ID, 187)
  field(:GENERAL_CHAT_CREATE, 188)
  field(:GENERAL_CHAT_ADD, 189)
  field(:GENERAL_CHAT_AUTO_ADD_DISABLED, 190)
  field(:SUGGESTED_SUBGROUP_ANNOUNCE, 191)
  field(:BIZ_BOT_1P_MESSAGING_ENABLED, 192)
  field(:CHANGE_USERNAME, 193)
  field(:BIZ_COEX_PRIVACY_INIT_SELF, 194)
  field(:BIZ_COEX_PRIVACY_TRANSITION_SELF, 195)
  field(:SUPPORT_AI_EDUCATION, 196)
  field(:BIZ_BOT_3P_MESSAGING_ENABLED, 197)
  field(:REMINDER_SETUP_MESSAGE, 198)
  field(:REMINDER_SENT_MESSAGE, 199)
  field(:REMINDER_CANCEL_MESSAGE, 200)
  field(:BIZ_COEX_PRIVACY_INIT, 201)
  field(:BIZ_COEX_PRIVACY_TRANSITION, 202)
  field(:GROUP_DEACTIVATED, 203)
  field(:COMMUNITY_DEACTIVATE_SIBLING_GROUP, 204)
  field(:EVENT_UPDATED, 205)
  field(:EVENT_CANCELED, 206)
  field(:COMMUNITY_OWNER_UPDATED, 207)
  field(:COMMUNITY_SUB_GROUP_VISIBILITY_HIDDEN, 208)
  field(:CAPI_GROUP_NE2EE_SYSTEM_MESSAGE, 209)
  field(:STATUS_MENTION, 210)
  field(:USER_CONTROLS_SYSTEM_MESSAGE, 211)
  field(:SUPPORT_SYSTEM_MESSAGE, 212)
  field(:CHANGE_LID, 213)
  field(:BIZ_CUSTOMER_3PD_DATA_SHARING_OPT_IN_MESSAGE, 214)
  field(:BIZ_CUSTOMER_3PD_DATA_SHARING_OPT_OUT_MESSAGE, 215)
  field(:CHANGE_LIMIT_SHARING, 216)
  field(:GROUP_MEMBER_LINK_MODE, 217)
  field(:BIZ_AUTOMATICALLY_LABELED_CHAT_SYSTEM_MESSAGE, 218)
  field(:PHONE_NUMBER_HIDING_CHAT_DEPRECATED_MESSAGE, 219)
  field(:QUARANTINED_MESSAGE, 220)
  field(:GROUP_MEMBER_SHARE_GROUP_HISTORY_MODE, 221)
end

defmodule Amarula.Protocol.Proto.ADVDeviceIdentity do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:rawId, 1, proto3_optional: true, type: :uint32)
  field(:timestamp, 2, proto3_optional: true, type: :uint64)
  field(:keyIndex, 3, proto3_optional: true, type: :uint32)

  field(:accountType, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ADVEncryptionType,
    enum: true
  )

  field(:deviceType, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ADVEncryptionType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.ADVKeyIndexList do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:rawId, 1, proto3_optional: true, type: :uint32)
  field(:timestamp, 2, proto3_optional: true, type: :uint64)
  field(:currentIndex, 3, proto3_optional: true, type: :uint32)
  field(:validIndexes, 4, repeated: true, type: :uint32, packed: true, deprecated: false)

  field(:accountType, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ADVEncryptionType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.ADVSignedDeviceIdentity do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:details, 1, proto3_optional: true, type: :bytes)
  field(:accountSignatureKey, 2, proto3_optional: true, type: :bytes)
  field(:accountSignature, 3, proto3_optional: true, type: :bytes)
  field(:deviceSignature, 4, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.ADVSignedDeviceIdentityHMAC do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:details, 1, proto3_optional: true, type: :bytes)
  field(:hmac, 2, proto3_optional: true, type: :bytes)

  field(:accountType, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ADVEncryptionType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.ADVSignedKeyIndexList do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:details, 1, proto3_optional: true, type: :bytes)
  field(:accountSignature, 2, proto3_optional: true, type: :bytes)
  field(:accountSignatureKey, 3, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.AIHomeState.AIHomeOption do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIHomeState.AIHomeOption.AIHomeActionType,
    enum: true
  )

  field(:title, 2, proto3_optional: true, type: :string)
  field(:promptText, 3, proto3_optional: true, type: :string)
  field(:sessionId, 4, proto3_optional: true, type: :string)
  field(:imageWdsIdentifier, 5, proto3_optional: true, type: :string)
  field(:imageTintColor, 6, proto3_optional: true, type: :string)
  field(:imageBackgroundColor, 7, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.AIHomeState do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:lastFetchTime, 1, proto3_optional: true, type: :int64)

  field(:capabilityOptions, 2,
    repeated: true,
    type: Amarula.Protocol.Proto.AIHomeState.AIHomeOption
  )

  field(:conversationOptions, 3,
    repeated: true,
    type: Amarula.Protocol.Proto.AIHomeState.AIHomeOption
  )
end

defmodule Amarula.Protocol.Proto.AIQueryFanout do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:message, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:timestamp, 3, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.AIRegenerateMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:responseTimestampMs, 2, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.AIRichResponseCodeMetadata.AIRichResponseCodeBlock do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:highlightType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseCodeMetadata.AIRichResponseCodeHighlightType,
    enum: true
  )

  field(:codeContent, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.AIRichResponseCodeMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:codeLanguage, 1, proto3_optional: true, type: :string)

  field(:codeBlocks, 2,
    repeated: true,
    type: Amarula.Protocol.Proto.AIRichResponseCodeMetadata.AIRichResponseCodeBlock
  )
end

defmodule Amarula.Protocol.Proto.AIRichResponseContentItemsMetadata.AIRichResponseContentItemMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:aIRichResponseContentItem, 0)

  field(:reelItem, 1,
    type: Amarula.Protocol.Proto.AIRichResponseContentItemsMetadata.AIRichResponseReelItem,
    oneof: 0
  )
end

defmodule Amarula.Protocol.Proto.AIRichResponseContentItemsMetadata.AIRichResponseReelItem do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, proto3_optional: true, type: :string)
  field(:profileIconUrl, 2, proto3_optional: true, type: :string)
  field(:thumbnailUrl, 3, proto3_optional: true, type: :string)
  field(:videoUrl, 4, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.AIRichResponseContentItemsMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:itemsMetadata, 1,
    repeated: true,
    type:
      Amarula.Protocol.Proto.AIRichResponseContentItemsMetadata.AIRichResponseContentItemMetadata
  )

  field(:contentType, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseContentItemsMetadata.ContentType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.AIRichResponseDynamicMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseDynamicMetadata.AIRichResponseDynamicMetadataType,
    enum: true
  )

  field(:version, 2, proto3_optional: true, type: :uint64)
  field(:url, 3, proto3_optional: true, type: :string)
  field(:loopCount, 4, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.AIRichResponseGridImageMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:gridImageUrl, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseImageURL
  )

  field(:imageUrls, 2, repeated: true, type: Amarula.Protocol.Proto.AIRichResponseImageURL)
end

defmodule Amarula.Protocol.Proto.AIRichResponseImageURL do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:imagePreviewUrl, 1, proto3_optional: true, type: :string)
  field(:imageHighResUrl, 2, proto3_optional: true, type: :string)
  field(:sourceUrl, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.AIRichResponseInlineImageMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:imageUrl, 1, proto3_optional: true, type: Amarula.Protocol.Proto.AIRichResponseImageURL)
  field(:imageText, 2, proto3_optional: true, type: :string)

  field(:alignment, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseInlineImageMetadata.AIRichResponseImageAlignment,
    enum: true
  )

  field(:tapLinkUrl, 4, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.AIRichResponseLatexMetadata.AIRichResponseLatexExpression do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:latexExpression, 1, proto3_optional: true, type: :string)
  field(:url, 2, proto3_optional: true, type: :string)
  field(:width, 3, proto3_optional: true, type: :double)
  field(:height, 4, proto3_optional: true, type: :double)
  field(:fontHeight, 5, proto3_optional: true, type: :double)
  field(:imageTopPadding, 6, proto3_optional: true, type: :double)
  field(:imageLeadingPadding, 7, proto3_optional: true, type: :double)
  field(:imageBottomPadding, 8, proto3_optional: true, type: :double)
  field(:imageTrailingPadding, 9, proto3_optional: true, type: :double)
end

defmodule Amarula.Protocol.Proto.AIRichResponseLatexMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:text, 1, proto3_optional: true, type: :string)

  field(:expressions, 2,
    repeated: true,
    type: Amarula.Protocol.Proto.AIRichResponseLatexMetadata.AIRichResponseLatexExpression
  )
end

defmodule Amarula.Protocol.Proto.AIRichResponseMapMetadata.AIRichResponseMapAnnotation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:annotationNumber, 1, proto3_optional: true, type: :uint32)
  field(:latitude, 2, proto3_optional: true, type: :double)
  field(:longitude, 3, proto3_optional: true, type: :double)
  field(:title, 4, proto3_optional: true, type: :string)
  field(:body, 5, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.AIRichResponseMapMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:centerLatitude, 1, proto3_optional: true, type: :double)
  field(:centerLongitude, 2, proto3_optional: true, type: :double)
  field(:latitudeDelta, 3, proto3_optional: true, type: :double)
  field(:longitudeDelta, 4, proto3_optional: true, type: :double)

  field(:annotations, 5,
    repeated: true,
    type: Amarula.Protocol.Proto.AIRichResponseMapMetadata.AIRichResponseMapAnnotation
  )

  field(:showInfoList, 6, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.AIRichResponseMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseMessageType,
    enum: true
  )

  field(:submessages, 2, repeated: true, type: Amarula.Protocol.Proto.AIRichResponseSubMessage)

  field(:unifiedResponse, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseUnifiedResponse
  )

  field(:contextInfo, 4, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.AIRichResponseSubMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseSubMessageType,
    enum: true
  )

  field(:gridImageMetadata, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseGridImageMetadata
  )

  field(:messageText, 3, proto3_optional: true, type: :string)

  field(:imageMetadata, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseInlineImageMetadata
  )

  field(:codeMetadata, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseCodeMetadata
  )

  field(:tableMetadata, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseTableMetadata
  )

  field(:dynamicMetadata, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseDynamicMetadata
  )

  field(:latexMetadata, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseLatexMetadata
  )

  field(:mapMetadata, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseMapMetadata
  )

  field(:contentItemsMetadata, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseContentItemsMetadata
  )
end

defmodule Amarula.Protocol.Proto.AIRichResponseTableMetadata.AIRichResponseTableRow do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:items, 1, repeated: true, type: :string)
  field(:isHeading, 2, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.AIRichResponseTableMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:rows, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.AIRichResponseTableMetadata.AIRichResponseTableRow
  )

  field(:title, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.AIRichResponseUnifiedResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:data, 1, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.AIThreadInfo.AIThreadClientInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIThreadInfo.AIThreadClientInfo.AIThreadType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.AIThreadInfo.AIThreadServerInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.AIThreadInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:serverInfo, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIThreadInfo.AIThreadServerInfo
  )

  field(:clientInfo, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIThreadInfo.AIThreadClientInfo
  )
end

defmodule Amarula.Protocol.Proto.Account do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:lid, 1, proto3_optional: true, type: :string)
  field(:username, 2, proto3_optional: true, type: :string)
  field(:countryCode, 3, proto3_optional: true, type: :string)
  field(:isUsernameDeleted, 4, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.ActionLink do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:url, 1, proto3_optional: true, type: :string)
  field(:buttonTitle, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.AutoDownloadSettings do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:downloadImages, 1, proto3_optional: true, type: :bool)
  field(:downloadAudio, 2, proto3_optional: true, type: :bool)
  field(:downloadVideo, 3, proto3_optional: true, type: :bool)
  field(:downloadDocuments, 4, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.AvatarUserSettings do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:fbid, 1, proto3_optional: true, type: :string)
  field(:password, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BizAccountLinkInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:whatsappBizAcctFbid, 1, proto3_optional: true, type: :uint64)
  field(:whatsappAcctNumber, 2, proto3_optional: true, type: :string)
  field(:issueTime, 3, proto3_optional: true, type: :uint64)

  field(:hostStorage, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BizAccountLinkInfo.HostStorageType,
    enum: true
  )

  field(:accountType, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BizAccountLinkInfo.AccountType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BizAccountPayload do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:vnameCert, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.VerifiedNameCertificate
  )

  field(:bizAcctLinkInfo, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.BizIdentityInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:vlevel, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BizIdentityInfo.VerifiedLevelValue,
    enum: true
  )

  field(:vnameCert, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.VerifiedNameCertificate
  )

  field(:signed, 3, proto3_optional: true, type: :bool)
  field(:revoked, 4, proto3_optional: true, type: :bool)

  field(:hostStorage, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BizIdentityInfo.HostStorageType,
    enum: true
  )

  field(:actualActors, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BizIdentityInfo.ActualActorsType,
    enum: true
  )

  field(:privacyModeTs, 7, proto3_optional: true, type: :uint64)
  field(:featureControls, 8, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.BotAgeCollectionMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ageCollectionEligible, 1, proto3_optional: true, type: :bool)
  field(:shouldTriggerAgeCollectionOnClient, 2, proto3_optional: true, type: :bool)

  field(:ageCollectionType, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotAgeCollectionMetadata.AgeCollectionType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BotAvatarMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sentiment, 1, proto3_optional: true, type: :uint32)
  field(:behaviorGraph, 2, proto3_optional: true, type: :string)
  field(:action, 3, proto3_optional: true, type: :uint32)
  field(:intensity, 4, proto3_optional: true, type: :uint32)
  field(:wordCount, 5, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.BotCapabilityMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:capabilities, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.BotCapabilityMetadata.BotCapabilityType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SideBySideSurveyAnalyticsData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:tessaEvent, 1, proto3_optional: true, type: :string)
  field(:tessaSessionFbid, 2, proto3_optional: true, type: :string)
  field(:simonSessionFbid, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData.SideBySideSurveyAbandonEventData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:abandonDwellTimeMsString, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData.SideBySideSurveyCTAClickEventData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isSurveyExpired, 1, proto3_optional: true, type: :bool)
  field(:clickDwellTimeMsString, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData.SideBySideSurveyCTAImpressionEventData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isSurveyExpired, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData.SideBySideSurveyCardImpressionEventData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData.SideBySideSurveyResponseEventData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:responseDwellTimeMsString, 1, proto3_optional: true, type: :string)
  field(:selectedResponseId, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:surveyId, 1, proto3_optional: true, type: :uint32)
  field(:primaryResponseId, 2, proto3_optional: true, type: :string)
  field(:testArmName, 3, proto3_optional: true, type: :string)
  field(:timestampMsString, 4, proto3_optional: true, type: :string)

  field(:ctaImpressionEvent, 5,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData.SideBySideSurveyCTAImpressionEventData
  )

  field(:ctaClickEvent, 6,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData.SideBySideSurveyCTAClickEventData
  )

  field(:cardImpressionEvent, 7,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData.SideBySideSurveyCardImpressionEventData
  )

  field(:responseEvent, 8,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData.SideBySideSurveyResponseEventData
  )

  field(:abandonEvent, 9,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData.SideBySideSurveyAbandonEventData
  )
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:selectedRequestId, 1, proto3_optional: true, type: :string)
  field(:surveyId, 2, proto3_optional: true, type: :uint32)
  field(:simonSessionFbid, 3, proto3_optional: true, type: :string)
  field(:responseOtid, 4, proto3_optional: true, type: :string)
  field(:responseTimestampMsString, 5, proto3_optional: true, type: :string)
  field(:isSelectedResponsePrimary, 6, proto3_optional: true, type: :bool)
  field(:messageIdToEdit, 7, proto3_optional: true, type: :string)

  field(:analyticsData, 8,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SideBySideSurveyAnalyticsData
  )

  field(:metaAiAnalyticsData, 9,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata.SidebySideSurveyMetaAiAnalyticsData
  )
end

defmodule Amarula.Protocol.Proto.BotFeedbackMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)

  field(:kind, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotFeedbackMessage.BotFeedbackKind,
    enum: true
  )

  field(:text, 3, proto3_optional: true, type: :string)
  field(:kindNegative, 4, proto3_optional: true, type: :uint64)
  field(:kindPositive, 5, proto3_optional: true, type: :uint64)

  field(:kindReport, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotFeedbackMessage.ReportKind,
    enum: true
  )

  field(:sideBySideSurveyMetadata, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotFeedbackMessage.SideBySideSurveyMetadata
  )
end

defmodule Amarula.Protocol.Proto.BotImagineMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:imagineType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotImagineMetadata.ImagineType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BotLinkedAccount do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotLinkedAccount.BotLinkedAccountType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BotLinkedAccountsMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:accounts, 1, repeated: true, type: Amarula.Protocol.Proto.BotLinkedAccount)
  field(:acAuthTokens, 2, proto3_optional: true, type: :bytes)
  field(:acErrorCode, 3, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.BotMediaMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:fileSha256, 1, proto3_optional: true, type: :string)
  field(:mediaKey, 2, proto3_optional: true, type: :string)
  field(:fileEncSha256, 3, proto3_optional: true, type: :string)
  field(:directPath, 4, proto3_optional: true, type: :string)
  field(:mediaKeyTimestamp, 5, proto3_optional: true, type: :int64)
  field(:mimetype, 6, proto3_optional: true, type: :string)

  field(:orientationType, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotMediaMetadata.OrientationType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BotMemoryFact do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:fact, 1, proto3_optional: true, type: :string)
  field(:factId, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotMemoryMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:addedFacts, 1, repeated: true, type: Amarula.Protocol.Proto.BotMemoryFact)
  field(:removedFacts, 2, repeated: true, type: Amarula.Protocol.Proto.BotMemoryFact)
  field(:disclaimer, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotMemuMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:faceImages, 1, repeated: true, type: Amarula.Protocol.Proto.BotMediaMetadata)
end

defmodule Amarula.Protocol.Proto.BotMessageOrigin do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotMessageOrigin.BotMessageOriginType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BotMessageOriginMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:origins, 1, repeated: true, type: Amarula.Protocol.Proto.BotMessageOrigin)
end

defmodule Amarula.Protocol.Proto.BotMessageSharingInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:botEntryPointOrigin, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotMetricsEntryPoint,
    enum: true
  )

  field(:forwardScore, 2, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.BotMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:avatarMetadata, 1, proto3_optional: true, type: Amarula.Protocol.Proto.BotAvatarMetadata)
  field(:personaId, 2, proto3_optional: true, type: :string)
  field(:pluginMetadata, 3, proto3_optional: true, type: Amarula.Protocol.Proto.BotPluginMetadata)

  field(:suggestedPromptMetadata, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotSuggestedPromptMetadata
  )

  field(:invokerJid, 5, proto3_optional: true, type: :string)

  field(:sessionMetadata, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotSessionMetadata
  )

  field(:memuMetadata, 7, proto3_optional: true, type: Amarula.Protocol.Proto.BotMemuMetadata)
  field(:timezone, 8, proto3_optional: true, type: :string)

  field(:reminderMetadata, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotReminderMetadata
  )

  field(:modelMetadata, 10, proto3_optional: true, type: Amarula.Protocol.Proto.BotModelMetadata)
  field(:messageDisclaimerText, 11, proto3_optional: true, type: :string)

  field(:progressIndicatorMetadata, 12,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotProgressIndicatorMetadata
  )

  field(:capabilityMetadata, 13,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotCapabilityMetadata
  )

  field(:imagineMetadata, 14,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotImagineMetadata
  )

  field(:memoryMetadata, 15,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotMemoryMetadata
  )

  field(:renderingMetadata, 16,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotRenderingMetadata
  )

  field(:botMetricsMetadata, 17,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotMetricsMetadata
  )

  field(:botLinkedAccountsMetadata, 18,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotLinkedAccountsMetadata
  )

  field(:richResponseSourcesMetadata, 19,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotSourcesMetadata
  )

  field(:aiConversationContext, 20, proto3_optional: true, type: :bytes)

  field(:botPromotionMessageMetadata, 21,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotPromotionMessageMetadata
  )

  field(:botModeSelectionMetadata, 22,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotModeSelectionMetadata
  )

  field(:botQuotaMetadata, 23,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotQuotaMetadata
  )

  field(:botAgeCollectionMetadata, 24,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotAgeCollectionMetadata
  )

  field(:conversationStarterPromptId, 25, proto3_optional: true, type: :string)
  field(:botResponseId, 26, proto3_optional: true, type: :string)

  field(:verificationMetadata, 27,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotSignatureVerificationMetadata
  )

  field(:unifiedResponseMutation, 28,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotUnifiedResponseMutation
  )

  field(:botMessageOriginMetadata, 29,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotMessageOriginMetadata
  )

  field(:inThreadSurveyMetadata, 30,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.InThreadSurveyMetadata
  )

  field(:botThreadInfo, 31, proto3_optional: true, type: Amarula.Protocol.Proto.AIThreadInfo)

  field(:regenerateMetadata, 32,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRegenerateMetadata
  )

  field(:sessionTransparencyMetadata, 33,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SessionTransparencyMetadata
  )

  field(:internalMetadata, 999, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.BotMetricsMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:destinationId, 1, proto3_optional: true, type: :string)

  field(:destinationEntryPoint, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotMetricsEntryPoint,
    enum: true
  )

  field(:threadOrigin, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotMetricsThreadEntryPoint,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BotModeSelectionMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:mode, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.BotModeSelectionMetadata.BotUserSelectionMode,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BotModelMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:modelType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotModelMetadata.ModelType,
    enum: true
  )

  field(:premiumModelStatus, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotModelMetadata.PremiumModelStatus,
    enum: true
  )

  field(:modelNameOverride, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotPluginMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:provider, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotPluginMetadata.SearchProvider,
    enum: true
  )

  field(:pluginType, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotPluginMetadata.PluginType,
    enum: true
  )

  field(:thumbnailCdnUrl, 3, proto3_optional: true, type: :string)
  field(:profilePhotoCdnUrl, 4, proto3_optional: true, type: :string)
  field(:searchProviderUrl, 5, proto3_optional: true, type: :string)
  field(:referenceIndex, 6, proto3_optional: true, type: :uint32)
  field(:expectedLinksCount, 7, proto3_optional: true, type: :uint32)
  field(:searchQuery, 9, proto3_optional: true, type: :string)

  field(:parentPluginMessageKey, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageKey
  )

  field(:deprecatedField, 11,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotPluginMetadata.PluginType,
    enum: true
  )

  field(:parentPluginType, 12,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotPluginMetadata.PluginType,
    enum: true
  )

  field(:faviconCdnUrl, 13, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.BotPlanningSearchSourceMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, proto3_optional: true, type: :string)

  field(:provider, 2,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.BotSearchSourceProvider,
    enum: true
  )

  field(:sourceUrl, 3, proto3_optional: true, type: :string)
  field(:favIconUrl, 4, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.BotPlanningSearchSourcesMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sourceTitle, 1, proto3_optional: true, type: :string)

  field(:provider, 2,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.BotPlanningSearchSourcesMetadata.BotPlanningSearchSourceProvider,
    enum: true
  )

  field(:sourceUrl, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.BotPlanningStepSectionMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sectionTitle, 1, proto3_optional: true, type: :string)
  field(:sectionBody, 2, proto3_optional: true, type: :string)

  field(:sourcesMetadata, 3,
    repeated: true,
    type:
      Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.BotPlanningSearchSourceMetadata
  )
end

defmodule Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:statusTitle, 1, proto3_optional: true, type: :string)
  field(:statusBody, 2, proto3_optional: true, type: :string)

  field(:sourcesMetadata, 3,
    repeated: true,
    type:
      Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.BotPlanningSearchSourcesMetadata
  )

  field(:status, 4,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.PlanningStepStatus,
    enum: true
  )

  field(:isReasoning, 5, proto3_optional: true, type: :bool)
  field(:isEnhancedSearch, 6, proto3_optional: true, type: :bool)

  field(:sections, 7,
    repeated: true,
    type:
      Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata.BotPlanningStepSectionMetadata
  )
end

defmodule Amarula.Protocol.Proto.BotProgressIndicatorMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:progressDescription, 1, proto3_optional: true, type: :string)

  field(:stepsMetadata, 2,
    repeated: true,
    type: Amarula.Protocol.Proto.BotProgressIndicatorMetadata.BotPlanningStepMetadata
  )
end

defmodule Amarula.Protocol.Proto.BotPromotionMessageMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:promotionType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotPromotionMessageMetadata.BotPromotionType,
    enum: true
  )

  field(:buttonTitle, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotPromptSuggestion do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:prompt, 1, proto3_optional: true, type: :string)
  field(:promptId, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotPromptSuggestions do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:suggestions, 1, repeated: true, type: Amarula.Protocol.Proto.BotPromptSuggestion)
end

defmodule Amarula.Protocol.Proto.BotQuotaMetadata.BotFeatureQuotaMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:featureType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotQuotaMetadata.BotFeatureQuotaMetadata.BotFeatureType,
    enum: true
  )

  field(:remainingQuota, 2, proto3_optional: true, type: :uint32)
  field(:expirationTimestamp, 3, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.BotQuotaMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:botFeatureQuotaMetadata, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.BotQuotaMetadata.BotFeatureQuotaMetadata
  )
end

defmodule Amarula.Protocol.Proto.BotReminderMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:requestMessageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)

  field(:action, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotReminderMetadata.ReminderAction,
    enum: true
  )

  field(:name, 3, proto3_optional: true, type: :string)
  field(:nextTriggerTimestamp, 4, proto3_optional: true, type: :uint64)

  field(:frequency, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotReminderMetadata.ReminderFrequency,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BotRenderingMetadata.Keyword do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:value, 1, proto3_optional: true, type: :string)
  field(:associatedPrompts, 2, repeated: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotRenderingMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:keywords, 1, repeated: true, type: Amarula.Protocol.Proto.BotRenderingMetadata.Keyword)
end

defmodule Amarula.Protocol.Proto.BotSessionMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sessionId, 1, proto3_optional: true, type: :string)

  field(:sessionSource, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotSessionSource,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.BotSignatureVerificationMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:proofs, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.BotSignatureVerificationUseCaseProof
  )
end

defmodule Amarula.Protocol.Proto.BotSignatureVerificationUseCaseProof do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:version, 1, proto3_optional: true, type: :int32)

  field(:useCase, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotSignatureVerificationUseCaseProof.BotSignatureUseCase,
    enum: true
  )

  field(:signature, 3, proto3_optional: true, type: :bytes)
  field(:certificateChain, 4, repeated: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.BotSourcesMetadata.BotSourceItem do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:provider, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotSourcesMetadata.BotSourceItem.SourceProvider,
    enum: true
  )

  field(:thumbnailCdnUrl, 2, proto3_optional: true, type: :string)
  field(:sourceProviderUrl, 3, proto3_optional: true, type: :string)
  field(:sourceQuery, 4, proto3_optional: true, type: :string)
  field(:faviconCdnUrl, 5, proto3_optional: true, type: :string)
  field(:citationNumber, 6, proto3_optional: true, type: :uint32)
  field(:sourceTitle, 7, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotSourcesMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sources, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.BotSourcesMetadata.BotSourceItem
  )
end

defmodule Amarula.Protocol.Proto.BotSuggestedPromptMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:suggestedPrompts, 1, repeated: true, type: :string)
  field(:selectedPromptIndex, 2, proto3_optional: true, type: :uint32)

  field(:promptSuggestions, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotPromptSuggestions
  )

  field(:selectedPromptId, 4, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.BotUnifiedResponseMutation.MediaDetailsMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :string)
  field(:highResMedia, 2, proto3_optional: true, type: Amarula.Protocol.Proto.BotMediaMetadata)
  field(:previewMedia, 3, proto3_optional: true, type: Amarula.Protocol.Proto.BotMediaMetadata)
end

defmodule Amarula.Protocol.Proto.BotUnifiedResponseMutation.SideBySideMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:primaryResponseId, 1, proto3_optional: true, type: :string)
  field(:surveyCtaHasRendered, 2, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.BotUnifiedResponseMutation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sbsMetadata, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotUnifiedResponseMutation.SideBySideMetadata
  )

  field(:mediaDetailsMetadataList, 2,
    repeated: true,
    type: Amarula.Protocol.Proto.BotUnifiedResponseMutation.MediaDetailsMetadata
  )
end

defmodule Amarula.Protocol.Proto.CallLogRecord.ParticipantInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:userJid, 1, proto3_optional: true, type: :string)

  field(:callResult, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.CallLogRecord.CallResult,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.CallLogRecord do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:callResult, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.CallLogRecord.CallResult,
    enum: true
  )

  field(:isDndMode, 2, proto3_optional: true, type: :bool)

  field(:silenceReason, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.CallLogRecord.SilenceReason,
    enum: true
  )

  field(:duration, 4, proto3_optional: true, type: :int64)
  field(:startTime, 5, proto3_optional: true, type: :int64)
  field(:isIncoming, 6, proto3_optional: true, type: :bool)
  field(:isVideo, 7, proto3_optional: true, type: :bool)
  field(:isCallLink, 8, proto3_optional: true, type: :bool)
  field(:callLinkToken, 9, proto3_optional: true, type: :string)
  field(:scheduledCallId, 10, proto3_optional: true, type: :string)
  field(:callId, 11, proto3_optional: true, type: :string)
  field(:callCreatorJid, 12, proto3_optional: true, type: :string)
  field(:groupJid, 13, proto3_optional: true, type: :string)

  field(:participants, 14,
    repeated: true,
    type: Amarula.Protocol.Proto.CallLogRecord.ParticipantInfo
  )

  field(:callType, 15,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.CallLogRecord.CallType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.CertChain.NoiseCertificate.Details do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:serial, 1, proto3_optional: true, type: :uint32)
  field(:issuerSerial, 2, proto3_optional: true, type: :uint32)
  field(:key, 3, proto3_optional: true, type: :bytes)
  field(:notBefore, 4, proto3_optional: true, type: :uint64)
  field(:notAfter, 5, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.CertChain.NoiseCertificate do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:details, 1, proto3_optional: true, type: :bytes)
  field(:signature, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.CertChain do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:leaf, 1, proto3_optional: true, type: Amarula.Protocol.Proto.CertChain.NoiseCertificate)

  field(:intermediate, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.CertChain.NoiseCertificate
  )
end

defmodule Amarula.Protocol.Proto.ChatLockSettings do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:hideLockedChats, 1, proto3_optional: true, type: :bool)
  field(:secretCode, 2, proto3_optional: true, type: Amarula.Protocol.Proto.UserPassword)
end

defmodule Amarula.Protocol.Proto.ChatRowOpaqueData.DraftMessage.CtwaContextData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:conversionSource, 1, proto3_optional: true, type: :string)
  field(:conversionData, 2, proto3_optional: true, type: :bytes)
  field(:sourceUrl, 3, proto3_optional: true, type: :string)
  field(:sourceId, 4, proto3_optional: true, type: :string)
  field(:sourceType, 5, proto3_optional: true, type: :string)
  field(:title, 6, proto3_optional: true, type: :string)
  field(:description, 7, proto3_optional: true, type: :string)
  field(:thumbnail, 8, proto3_optional: true, type: :string)
  field(:thumbnailUrl, 9, proto3_optional: true, type: :string)

  field(:mediaType, 10,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.ChatRowOpaqueData.DraftMessage.CtwaContextData.ContextInfoExternalAdReplyInfoMediaType,
    enum: true
  )

  field(:mediaUrl, 11, proto3_optional: true, type: :string)
  field(:isSuspiciousLink, 12, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.ChatRowOpaqueData.DraftMessage.CtwaContextLinkData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:context, 1, proto3_optional: true, type: :string)
  field(:sourceUrl, 2, proto3_optional: true, type: :string)
  field(:icebreaker, 3, proto3_optional: true, type: :string)
  field(:phone, 4, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.ChatRowOpaqueData.DraftMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:text, 1, proto3_optional: true, type: :string)
  field(:omittedUrl, 2, proto3_optional: true, type: :string)

  field(:ctwaContextLinkData, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ChatRowOpaqueData.DraftMessage.CtwaContextLinkData
  )

  field(:ctwaContext, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ChatRowOpaqueData.DraftMessage.CtwaContextData
  )

  field(:timestamp, 5, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.ChatRowOpaqueData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:draftMessage, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ChatRowOpaqueData.DraftMessage
  )
end

defmodule Amarula.Protocol.Proto.Citation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, type: :string)
  field(:subtitle, 2, type: :string)
  field(:cmsId, 3, type: :string)
  field(:imageUrl, 4, type: :string)
end

defmodule Amarula.Protocol.Proto.ClientPairingProps do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isChatDbLidMigrated, 1, proto3_optional: true, type: :bool)
  field(:isSyncdPureLidSession, 2, proto3_optional: true, type: :bool)
  field(:isSyncdSnapshotRecoveryEnabled, 3, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.ClientPayload.DNSSource do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:dnsMethod, 15,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.DNSSource.DNSResolutionMethod,
    enum: true
  )

  field(:appCached, 16, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.ClientPayload.DevicePairingRegistrationData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:eRegid, 1, proto3_optional: true, type: :bytes)
  field(:eKeytype, 2, proto3_optional: true, type: :bytes)
  field(:eIdent, 3, proto3_optional: true, type: :bytes)
  field(:eSkeyId, 4, proto3_optional: true, type: :bytes)
  field(:eSkeyVal, 5, proto3_optional: true, type: :bytes)
  field(:eSkeySig, 6, proto3_optional: true, type: :bytes)
  field(:buildHash, 7, proto3_optional: true, type: :bytes)
  field(:deviceProps, 8, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.ClientPayload.InteropData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:accountId, 1, proto3_optional: true, type: :uint64)
  field(:token, 2, proto3_optional: true, type: :bytes)
  field(:enableReadReceipts, 3, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.ClientPayload.UserAgent.AppVersion do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:primary, 1, proto3_optional: true, type: :uint32)
  field(:secondary, 2, proto3_optional: true, type: :uint32)
  field(:tertiary, 3, proto3_optional: true, type: :uint32)
  field(:quaternary, 4, proto3_optional: true, type: :uint32)
  field(:quinary, 5, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.ClientPayload.UserAgent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:platform, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.UserAgent.Platform,
    enum: true
  )

  field(:appVersion, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.UserAgent.AppVersion
  )

  field(:mcc, 3, proto3_optional: true, type: :string)
  field(:mnc, 4, proto3_optional: true, type: :string)
  field(:osVersion, 5, proto3_optional: true, type: :string)
  field(:manufacturer, 6, proto3_optional: true, type: :string)
  field(:device, 7, proto3_optional: true, type: :string)
  field(:osBuildNumber, 8, proto3_optional: true, type: :string)
  field(:phoneId, 9, proto3_optional: true, type: :string)

  field(:releaseChannel, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.UserAgent.ReleaseChannel,
    enum: true
  )

  field(:localeLanguageIso6391, 11, proto3_optional: true, type: :string)
  field(:localeCountryIso31661Alpha2, 12, proto3_optional: true, type: :string)
  field(:deviceBoard, 13, proto3_optional: true, type: :string)
  field(:deviceExpId, 14, proto3_optional: true, type: :string)

  field(:deviceType, 15,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.UserAgent.DeviceType,
    enum: true
  )

  field(:deviceModelType, 16, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.ClientPayload.WebInfo.WebdPayload do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:usesParticipantInKey, 1, proto3_optional: true, type: :bool)
  field(:supportsStarredMessages, 2, proto3_optional: true, type: :bool)
  field(:supportsDocumentMessages, 3, proto3_optional: true, type: :bool)
  field(:supportsUrlMessages, 4, proto3_optional: true, type: :bool)
  field(:supportsMediaRetry, 5, proto3_optional: true, type: :bool)
  field(:supportsE2EImage, 6, proto3_optional: true, type: :bool)
  field(:supportsE2EVideo, 7, proto3_optional: true, type: :bool)
  field(:supportsE2EAudio, 8, proto3_optional: true, type: :bool)
  field(:supportsE2EDocument, 9, proto3_optional: true, type: :bool)
  field(:documentTypes, 10, proto3_optional: true, type: :string)
  field(:features, 11, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.ClientPayload.WebInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:refToken, 1, proto3_optional: true, type: :string)
  field(:version, 2, proto3_optional: true, type: :string)

  field(:webdPayload, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.WebInfo.WebdPayload
  )

  field(:webSubPlatform, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.WebInfo.WebSubPlatform,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.ClientPayload do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:username, 1, proto3_optional: true, type: :uint64)
  field(:passive, 3, proto3_optional: true, type: :bool)

  field(:userAgent, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.UserAgent
  )

  field(:webInfo, 6, proto3_optional: true, type: Amarula.Protocol.Proto.ClientPayload.WebInfo)
  field(:pushName, 7, proto3_optional: true, type: :string)
  field(:sessionId, 9, proto3_optional: true, type: :sfixed32)
  field(:shortConnect, 10, proto3_optional: true, type: :bool)

  field(:connectType, 12,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.ConnectType,
    enum: true
  )

  field(:connectReason, 13,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.ConnectReason,
    enum: true
  )

  field(:shards, 14, repeated: true, type: :int32)

  field(:dnsSource, 15,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.DNSSource
  )

  field(:connectAttemptCount, 16, proto3_optional: true, type: :uint32)
  field(:device, 18, proto3_optional: true, type: :uint32)

  field(:devicePairingData, 19,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.DevicePairingRegistrationData
  )

  field(:product, 20,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.Product,
    enum: true
  )

  field(:fbCat, 21, proto3_optional: true, type: :bytes)
  field(:fbUserAgent, 22, proto3_optional: true, type: :bytes)
  field(:oc, 23, proto3_optional: true, type: :bool)
  field(:lc, 24, proto3_optional: true, type: :int32)

  field(:iosAppExtension, 30,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.IOSAppExtension,
    enum: true
  )

  field(:fbAppId, 31, proto3_optional: true, type: :uint64)
  field(:fbDeviceId, 32, proto3_optional: true, type: :bytes)
  field(:pull, 33, proto3_optional: true, type: :bool)
  field(:paddingBytes, 34, proto3_optional: true, type: :bytes)
  field(:yearClass, 36, proto3_optional: true, type: :int32)
  field(:memClass, 37, proto3_optional: true, type: :int32)

  field(:interopData, 38,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.InteropData
  )

  field(:trafficAnonymization, 40,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.TrafficAnonymization,
    enum: true
  )

  field(:lidDbMigrated, 41, proto3_optional: true, type: :bool)

  field(:accountType, 42,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ClientPayload.AccountType,
    enum: true
  )

  field(:connectionSequenceInfo, 43, proto3_optional: true, type: :sfixed32)
  field(:paaLink, 44, proto3_optional: true, type: :bool)
  field(:preacksCount, 45, proto3_optional: true, type: :int32)
  field(:processingQueueSize, 46, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.CommentMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:commentParentKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:replyCount, 2, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.CompanionCommitment do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:hash, 1, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.CompanionEphemeralIdentity do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:publicKey, 1, proto3_optional: true, type: :bytes)

  field(:deviceType, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceProps.PlatformType,
    enum: true
  )

  field(:ref, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Config.FieldEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :uint32)
  field(:value, 2, type: Amarula.Protocol.Proto.Field)
end

defmodule Amarula.Protocol.Proto.Config do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:field, 1, repeated: true, type: Amarula.Protocol.Proto.Config.FieldEntry, map: true)
  field(:version, 2, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.ContextInfo.AdReplyInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:advertiserName, 1, proto3_optional: true, type: :string)

  field(:mediaType, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.AdReplyInfo.MediaType,
    enum: true
  )

  field(:jpegThumbnail, 16, proto3_optional: true, type: :bytes)
  field(:caption, 17, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.ContextInfo.BusinessMessageForwardInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:businessOwnerJid, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.ContextInfo.DataSharingContext.Parameters do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: :string)
  field(:stringData, 2, proto3_optional: true, type: :string)
  field(:intData, 3, proto3_optional: true, type: :int64)
  field(:floatData, 4, proto3_optional: true, type: :float)

  field(:contents, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.DataSharingContext.Parameters
  )
end

defmodule Amarula.Protocol.Proto.ContextInfo.DataSharingContext do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:showMmDisclosure, 1, proto3_optional: true, type: :bool)
  field(:encryptedSignalTokenConsented, 2, proto3_optional: true, type: :string)

  field(:parameters, 3,
    repeated: true,
    type: Amarula.Protocol.Proto.ContextInfo.DataSharingContext.Parameters
  )

  field(:dataSharingFlags, 4, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.ContextInfo.ExternalAdReplyInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, proto3_optional: true, type: :string)
  field(:body, 2, proto3_optional: true, type: :string)

  field(:mediaType, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.ExternalAdReplyInfo.MediaType,
    enum: true
  )

  field(:thumbnailUrl, 4, proto3_optional: true, type: :string)
  field(:mediaUrl, 5, proto3_optional: true, type: :string)
  field(:thumbnail, 6, proto3_optional: true, type: :bytes)
  field(:sourceType, 7, proto3_optional: true, type: :string)
  field(:sourceId, 8, proto3_optional: true, type: :string)
  field(:sourceUrl, 9, proto3_optional: true, type: :string)
  field(:containsAutoReply, 10, proto3_optional: true, type: :bool)
  field(:renderLargerThumbnail, 11, proto3_optional: true, type: :bool)
  field(:showAdAttribution, 12, proto3_optional: true, type: :bool)
  field(:ctwaClid, 13, proto3_optional: true, type: :string)
  field(:ref, 14, proto3_optional: true, type: :string)
  field(:clickToWhatsappCall, 15, proto3_optional: true, type: :bool)
  field(:adContextPreviewDismissed, 16, proto3_optional: true, type: :bool)
  field(:sourceApp, 17, proto3_optional: true, type: :string)
  field(:automatedGreetingMessageShown, 18, proto3_optional: true, type: :bool)
  field(:greetingMessageBody, 19, proto3_optional: true, type: :string)
  field(:ctaPayload, 20, proto3_optional: true, type: :string)
  field(:disableNudge, 21, proto3_optional: true, type: :bool)
  field(:originalImageUrl, 22, proto3_optional: true, type: :string)
  field(:automatedGreetingMessageCtaType, 23, proto3_optional: true, type: :string)
  field(:wtwaAdFormat, 24, proto3_optional: true, type: :bool)

  field(:adType, 25,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.ExternalAdReplyInfo.AdType,
    enum: true
  )

  field(:wtwaWebsiteUrl, 26, proto3_optional: true, type: :string)
  field(:adPreviewUrl, 27, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.ContextInfo.FeatureEligibilities do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:cannotBeReactedTo, 1, proto3_optional: true, type: :bool)
  field(:cannotBeRanked, 2, proto3_optional: true, type: :bool)
  field(:canRequestFeedback, 3, proto3_optional: true, type: :bool)
  field(:canBeReshared, 4, proto3_optional: true, type: :bool)
  field(:canReceiveMultiReact, 5, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.ContextInfo.ForwardedNewsletterMessageInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:newsletterJid, 1, proto3_optional: true, type: :string)
  field(:serverMessageId, 2, proto3_optional: true, type: :int32)
  field(:newsletterName, 3, proto3_optional: true, type: :string)

  field(:contentType, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.ForwardedNewsletterMessageInfo.ContentType,
    enum: true
  )

  field(:accessibilityText, 5, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.ContextInfo.QuestionReplyQuotedMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:serverQuestionId, 1, proto3_optional: true, type: :int32)
  field(:quotedQuestion, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:quotedResponse, 3, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
end

defmodule Amarula.Protocol.Proto.ContextInfo.StatusAudienceMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:audienceType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.StatusAudienceMetadata.AudienceType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.ContextInfo.UTMInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:utmSource, 1, proto3_optional: true, type: :string)
  field(:utmCampaign, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.ContextInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:stanzaId, 1, proto3_optional: true, type: :string)
  field(:participant, 2, proto3_optional: true, type: :string)
  field(:quotedMessage, 3, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:remoteJid, 4, proto3_optional: true, type: :string)
  field(:mentionedJid, 15, repeated: true, type: :string)
  field(:conversionSource, 18, proto3_optional: true, type: :string)
  field(:conversionData, 19, proto3_optional: true, type: :bytes)
  field(:conversionDelaySeconds, 20, proto3_optional: true, type: :uint32)
  field(:forwardingScore, 21, proto3_optional: true, type: :uint32)
  field(:isForwarded, 22, proto3_optional: true, type: :bool)

  field(:quotedAd, 23,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.AdReplyInfo
  )

  field(:placeholderKey, 24, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:expiration, 25, proto3_optional: true, type: :uint32)
  field(:ephemeralSettingTimestamp, 26, proto3_optional: true, type: :int64)
  field(:ephemeralSharedSecret, 27, proto3_optional: true, type: :bytes)

  field(:externalAdReply, 28,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.ExternalAdReplyInfo
  )

  field(:entryPointConversionSource, 29, proto3_optional: true, type: :string)
  field(:entryPointConversionApp, 30, proto3_optional: true, type: :string)
  field(:entryPointConversionDelaySeconds, 31, proto3_optional: true, type: :uint32)

  field(:disappearingMode, 32,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DisappearingMode
  )

  field(:actionLink, 33, proto3_optional: true, type: Amarula.Protocol.Proto.ActionLink)
  field(:groupSubject, 34, proto3_optional: true, type: :string)
  field(:parentGroupJid, 35, proto3_optional: true, type: :string)
  field(:trustBannerType, 37, proto3_optional: true, type: :string)
  field(:trustBannerAction, 38, proto3_optional: true, type: :uint32)
  field(:isSampled, 39, proto3_optional: true, type: :bool)
  field(:groupMentions, 40, repeated: true, type: Amarula.Protocol.Proto.GroupMention)
  field(:utm, 41, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo.UTMInfo)

  field(:forwardedNewsletterMessageInfo, 43,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.ForwardedNewsletterMessageInfo
  )

  field(:businessMessageForwardInfo, 44,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.BusinessMessageForwardInfo
  )

  field(:smbClientCampaignId, 45, proto3_optional: true, type: :string)
  field(:smbServerCampaignId, 46, proto3_optional: true, type: :string)

  field(:dataSharingContext, 47,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.DataSharingContext
  )

  field(:alwaysShowAdAttribution, 48, proto3_optional: true, type: :bool)

  field(:featureEligibilities, 49,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.FeatureEligibilities
  )

  field(:entryPointConversionExternalSource, 50, proto3_optional: true, type: :string)
  field(:entryPointConversionExternalMedium, 51, proto3_optional: true, type: :string)
  field(:ctwaSignals, 54, proto3_optional: true, type: :string)
  field(:ctwaPayload, 55, proto3_optional: true, type: :bytes)

  field(:forwardedAiBotMessageInfo, 56,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ForwardedAIBotMessageInfo
  )

  field(:statusAttributionType, 57,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.StatusAttributionType,
    enum: true
  )

  field(:urlTrackingMap, 58, proto3_optional: true, type: Amarula.Protocol.Proto.UrlTrackingMap)

  field(:pairedMediaType, 59,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.PairedMediaType,
    enum: true
  )

  field(:rankingVersion, 60, proto3_optional: true, type: :uint32)
  field(:memberLabel, 62, proto3_optional: true, type: Amarula.Protocol.Proto.MemberLabel)
  field(:isQuestion, 63, proto3_optional: true, type: :bool)

  field(:statusSourceType, 64,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.StatusSourceType,
    enum: true
  )

  field(:statusAttributions, 65, repeated: true, type: Amarula.Protocol.Proto.StatusAttribution)
  field(:isGroupStatus, 66, proto3_optional: true, type: :bool)

  field(:forwardOrigin, 67,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.ForwardOrigin,
    enum: true
  )

  field(:questionReplyQuotedMessage, 68,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.QuestionReplyQuotedMessage
  )

  field(:statusAudienceMetadata, 69,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.StatusAudienceMetadata
  )

  field(:nonJidMentions, 70, proto3_optional: true, type: :uint32)

  field(:quotedType, 71,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ContextInfo.QuotedType,
    enum: true
  )

  field(:botMessageSharingInfo, 72,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotMessageSharingInfo
  )
end

defmodule Amarula.Protocol.Proto.Conversation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, type: :string)
  field(:messages, 2, repeated: true, type: Amarula.Protocol.Proto.HistorySyncMsg)
  field(:newJid, 3, proto3_optional: true, type: :string)
  field(:oldJid, 4, proto3_optional: true, type: :string)
  field(:lastMsgTimestamp, 5, proto3_optional: true, type: :uint64)
  field(:unreadCount, 6, proto3_optional: true, type: :uint32)
  field(:readOnly, 7, proto3_optional: true, type: :bool)
  field(:endOfHistoryTransfer, 8, proto3_optional: true, type: :bool)
  field(:ephemeralExpiration, 9, proto3_optional: true, type: :uint32)
  field(:ephemeralSettingTimestamp, 10, proto3_optional: true, type: :int64)

  field(:endOfHistoryTransferType, 11,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Conversation.EndOfHistoryTransferType,
    enum: true
  )

  field(:conversationTimestamp, 12, proto3_optional: true, type: :uint64)
  field(:name, 13, proto3_optional: true, type: :string)
  field(:pHash, 14, proto3_optional: true, type: :string)
  field(:notSpam, 15, proto3_optional: true, type: :bool)
  field(:archived, 16, proto3_optional: true, type: :bool)

  field(:disappearingMode, 17,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DisappearingMode
  )

  field(:unreadMentionCount, 18, proto3_optional: true, type: :uint32)
  field(:markedAsUnread, 19, proto3_optional: true, type: :bool)
  field(:participant, 20, repeated: true, type: Amarula.Protocol.Proto.GroupParticipant)
  field(:tcToken, 21, proto3_optional: true, type: :bytes)
  field(:tcTokenTimestamp, 22, proto3_optional: true, type: :uint64)
  field(:contactPrimaryIdentityKey, 23, proto3_optional: true, type: :bytes)
  field(:pinned, 24, proto3_optional: true, type: :uint32)
  field(:muteEndTime, 25, proto3_optional: true, type: :uint64)
  field(:wallpaper, 26, proto3_optional: true, type: Amarula.Protocol.Proto.WallpaperSettings)

  field(:mediaVisibility, 27,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MediaVisibility,
    enum: true
  )

  field(:tcTokenSenderTimestamp, 28, proto3_optional: true, type: :uint64)
  field(:suspended, 29, proto3_optional: true, type: :bool)
  field(:terminated, 30, proto3_optional: true, type: :bool)
  field(:createdAt, 31, proto3_optional: true, type: :uint64)
  field(:createdBy, 32, proto3_optional: true, type: :string)
  field(:description, 33, proto3_optional: true, type: :string)
  field(:support, 34, proto3_optional: true, type: :bool)
  field(:isParentGroup, 35, proto3_optional: true, type: :bool)
  field(:parentGroupId, 37, proto3_optional: true, type: :string)
  field(:isDefaultSubgroup, 36, proto3_optional: true, type: :bool)
  field(:displayName, 38, proto3_optional: true, type: :string)
  field(:pnJid, 39, proto3_optional: true, type: :string)
  field(:shareOwnPn, 40, proto3_optional: true, type: :bool)
  field(:pnhDuplicateLidThread, 41, proto3_optional: true, type: :bool)
  field(:lidJid, 42, proto3_optional: true, type: :string)
  field(:username, 43, proto3_optional: true, type: :string)
  field(:lidOriginType, 44, proto3_optional: true, type: :string)
  field(:commentsCount, 45, proto3_optional: true, type: :uint32)
  field(:locked, 46, proto3_optional: true, type: :bool)

  field(:systemMessageToInsert, 47,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.PrivacySystemMessage,
    enum: true
  )

  field(:capiCreatedGroup, 48, proto3_optional: true, type: :bool)
  field(:accountLid, 49, proto3_optional: true, type: :string)
  field(:limitSharing, 50, proto3_optional: true, type: :bool)
  field(:limitSharingSettingTimestamp, 51, proto3_optional: true, type: :int64)

  field(:limitSharingTrigger, 52,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.LimitSharing.TriggerType,
    enum: true
  )

  field(:limitSharingInitiatedByMe, 53, proto3_optional: true, type: :bool)
  field(:maibaAiThreadEnabled, 54, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.DeviceCapabilities.BusinessBroadcast do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:importListEnabled, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.DeviceCapabilities.LIDMigration do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:chatDbMigrationTimestamp, 1, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.DeviceCapabilities.UserHasAvatar do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:userHasAvatar, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.DeviceCapabilities do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:chatLockSupportLevel, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceCapabilities.ChatLockSupportLevel,
    enum: true
  )

  field(:lidMigration, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceCapabilities.LIDMigration
  )

  field(:businessBroadcast, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceCapabilities.BusinessBroadcast
  )

  field(:userHasAvatar, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceCapabilities.UserHasAvatar
  )

  field(:memberNameTagPrimarySupport, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceCapabilities.MemberNameTagPrimarySupport,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.DeviceConsistencyCodeMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:generation, 1, proto3_optional: true, type: :uint32)
  field(:signature, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.DeviceListMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:senderKeyHash, 1, proto3_optional: true, type: :bytes)
  field(:senderTimestamp, 2, proto3_optional: true, type: :uint64)
  field(:senderKeyIndexes, 3, repeated: true, type: :uint32, packed: true, deprecated: false)

  field(:senderAccountType, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ADVEncryptionType,
    enum: true
  )

  field(:receiverAccountType, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ADVEncryptionType,
    enum: true
  )

  field(:recipientKeyHash, 8, proto3_optional: true, type: :bytes)
  field(:recipientTimestamp, 9, proto3_optional: true, type: :uint64)
  field(:recipientKeyIndexes, 10, repeated: true, type: :uint32, packed: true, deprecated: false)
end

defmodule Amarula.Protocol.Proto.DeviceProps.AppVersion do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:primary, 1, proto3_optional: true, type: :uint32)
  field(:secondary, 2, proto3_optional: true, type: :uint32)
  field(:tertiary, 3, proto3_optional: true, type: :uint32)
  field(:quaternary, 4, proto3_optional: true, type: :uint32)
  field(:quinary, 5, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.DeviceProps.HistorySyncConfig do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:fullSyncDaysLimit, 1, proto3_optional: true, type: :uint32)
  field(:fullSyncSizeMbLimit, 2, proto3_optional: true, type: :uint32)
  field(:storageQuotaMb, 3, proto3_optional: true, type: :uint32)
  field(:inlineInitialPayloadInE2EeMsg, 4, proto3_optional: true, type: :bool)
  field(:recentSyncDaysLimit, 5, proto3_optional: true, type: :uint32)
  field(:supportCallLogHistory, 6, proto3_optional: true, type: :bool)
  field(:supportBotUserAgentChatHistory, 7, proto3_optional: true, type: :bool)
  field(:supportCagReactionsAndPolls, 8, proto3_optional: true, type: :bool)
  field(:supportBizHostedMsg, 9, proto3_optional: true, type: :bool)
  field(:supportRecentSyncChunkMessageCountTuning, 10, proto3_optional: true, type: :bool)
  field(:supportHostedGroupMsg, 11, proto3_optional: true, type: :bool)
  field(:supportFbidBotChatHistory, 12, proto3_optional: true, type: :bool)
  field(:supportAddOnHistorySyncMigration, 13, proto3_optional: true, type: :bool)
  field(:supportMessageAssociation, 14, proto3_optional: true, type: :bool)
  field(:supportGroupHistory, 15, proto3_optional: true, type: :bool)
  field(:onDemandReady, 16, proto3_optional: true, type: :bool)
  field(:supportGuestChat, 17, proto3_optional: true, type: :bool)
  field(:completeOnDemandReady, 18, proto3_optional: true, type: :bool)
  field(:thumbnailSyncDaysLimit, 19, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.DeviceProps do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:os, 1, proto3_optional: true, type: :string)
  field(:version, 2, proto3_optional: true, type: Amarula.Protocol.Proto.DeviceProps.AppVersion)

  field(:platformType, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceProps.PlatformType,
    enum: true
  )

  field(:requireFullSync, 4, proto3_optional: true, type: :bool)

  field(:historySyncConfig, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceProps.HistorySyncConfig
  )
end

defmodule Amarula.Protocol.Proto.DisappearingMode do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:initiator, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DisappearingMode.Initiator,
    enum: true
  )

  field(:trigger, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DisappearingMode.Trigger,
    enum: true
  )

  field(:initiatorDeviceJid, 3, proto3_optional: true, type: :string)
  field(:initiatedByMe, 4, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.EmbeddedContent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:content, 0)

  field(:embeddedMessage, 1, type: Amarula.Protocol.Proto.EmbeddedMessage, oneof: 0)
  field(:embeddedMusic, 2, type: Amarula.Protocol.Proto.EmbeddedMusic, oneof: 0)
end

defmodule Amarula.Protocol.Proto.EmbeddedMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:stanzaId, 1, proto3_optional: true, type: :string)
  field(:message, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
end

defmodule Amarula.Protocol.Proto.EmbeddedMusic do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:musicContentMediaId, 1, proto3_optional: true, type: :string)
  field(:songId, 2, proto3_optional: true, type: :string)
  field(:author, 3, proto3_optional: true, type: :string)
  field(:title, 4, proto3_optional: true, type: :string)
  field(:artworkDirectPath, 5, proto3_optional: true, type: :string)
  field(:artworkSha256, 6, proto3_optional: true, type: :bytes)
  field(:artworkEncSha256, 7, proto3_optional: true, type: :bytes)
  field(:artistAttribution, 8, proto3_optional: true, type: :string)
  field(:countryBlocklist, 9, proto3_optional: true, type: :bytes)
  field(:isExplicit, 10, proto3_optional: true, type: :bool)
  field(:artworkMediaKey, 11, proto3_optional: true, type: :bytes)
  field(:musicSongStartTimeInMs, 12, proto3_optional: true, type: :int64)
  field(:derivedContentStartTimeInMs, 13, proto3_optional: true, type: :int64)
  field(:overlapDurationInMs, 14, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.EncryptedPairingRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:encryptedPayload, 1, proto3_optional: true, type: :bytes)
  field(:iv, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.EphemeralSetting do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:duration, 1, proto3_optional: true, type: :sfixed32)
  field(:timestamp, 2, proto3_optional: true, type: :sfixed64)
end

defmodule Amarula.Protocol.Proto.EventAdditionalMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isStale, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.EventResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:eventResponseMessageKey, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageKey
  )

  field(:timestampMs, 2, proto3_optional: true, type: :int64)

  field(:eventResponseMessage, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.EventResponseMessage
  )

  field(:unread, 4, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.ExitCode do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:code, 1, proto3_optional: true, type: :uint64)
  field(:text, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.ExternalBlobReference do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:mediaKey, 1, proto3_optional: true, type: :bytes)
  field(:directPath, 2, proto3_optional: true, type: :string)
  field(:handle, 3, proto3_optional: true, type: :string)
  field(:fileSizeBytes, 4, proto3_optional: true, type: :uint64)
  field(:fileSha256, 5, proto3_optional: true, type: :bytes)
  field(:fileEncSha256, 6, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Field.SubfieldEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :uint32)
  field(:value, 2, type: Amarula.Protocol.Proto.Field)
end

defmodule Amarula.Protocol.Proto.Field do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:minVersion, 1, proto3_optional: true, type: :uint32)
  field(:maxVersion, 2, proto3_optional: true, type: :uint32)
  field(:notReportableMinVersion, 3, proto3_optional: true, type: :uint32)
  field(:isMessage, 4, proto3_optional: true, type: :bool)
  field(:subfield, 5, repeated: true, type: Amarula.Protocol.Proto.Field.SubfieldEntry, map: true)
end

defmodule Amarula.Protocol.Proto.ForwardedAIBotMessageInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:botName, 1, proto3_optional: true, type: :string)
  field(:botJid, 2, proto3_optional: true, type: :string)
  field(:creatorName, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.GlobalSettings do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:lightThemeWallpaper, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WallpaperSettings
  )

  field(:mediaVisibility, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MediaVisibility,
    enum: true
  )

  field(:darkThemeWallpaper, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WallpaperSettings
  )

  field(:autoDownloadWiFi, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AutoDownloadSettings
  )

  field(:autoDownloadCellular, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AutoDownloadSettings
  )

  field(:autoDownloadRoaming, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AutoDownloadSettings
  )

  field(:showIndividualNotificationsPreview, 7, proto3_optional: true, type: :bool)
  field(:showGroupNotificationsPreview, 8, proto3_optional: true, type: :bool)
  field(:disappearingModeDuration, 9, proto3_optional: true, type: :int32)
  field(:disappearingModeTimestamp, 10, proto3_optional: true, type: :int64)

  field(:avatarUserSettings, 11,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AvatarUserSettings
  )

  field(:fontSize, 12, proto3_optional: true, type: :int32)
  field(:securityNotifications, 13, proto3_optional: true, type: :bool)
  field(:autoUnarchiveChats, 14, proto3_optional: true, type: :bool)
  field(:videoQualityMode, 15, proto3_optional: true, type: :int32)
  field(:photoQualityMode, 16, proto3_optional: true, type: :int32)

  field(:individualNotificationSettings, 17,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.NotificationSettings
  )

  field(:groupNotificationSettings, 18,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.NotificationSettings
  )

  field(:chatLockSettings, 19,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ChatLockSettings
  )

  field(:chatDbLidMigrationTimestamp, 20, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.GroupHistoryBundleInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:deprecatedMessageHistoryBundle, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MessageHistoryBundle
  )

  field(:processState, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.GroupHistoryBundleInfo.ProcessState,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.GroupHistoryIndividualMessageInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:bundleMessageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:editedAfterReceivedAsHistory, 2, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.GroupMention do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:groupJid, 1, proto3_optional: true, type: :string)
  field(:groupSubject, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.GroupParticipant do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:userJid, 1, type: :string)

  field(:rank, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.GroupParticipant.Rank,
    enum: true
  )

  field(:memberLabel, 3, proto3_optional: true, type: Amarula.Protocol.Proto.MemberLabel)
end

defmodule Amarula.Protocol.Proto.HandshakeMessage.ClientFinish do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:static, 1, proto3_optional: true, type: :bytes)
  field(:payload, 2, proto3_optional: true, type: :bytes)
  field(:extendedCiphertext, 3, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.HandshakeMessage.ClientHello do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ephemeral, 1, proto3_optional: true, type: :bytes)
  field(:static, 2, proto3_optional: true, type: :bytes)
  field(:payload, 3, proto3_optional: true, type: :bytes)
  field(:useExtended, 4, proto3_optional: true, type: :bool)
  field(:extendedCiphertext, 5, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.HandshakeMessage.ServerHello do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ephemeral, 1, proto3_optional: true, type: :bytes)
  field(:static, 2, proto3_optional: true, type: :bytes)
  field(:payload, 3, proto3_optional: true, type: :bytes)
  field(:extendedStatic, 4, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.HandshakeMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:clientHello, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.HandshakeMessage.ClientHello
  )

  field(:serverHello, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.HandshakeMessage.ServerHello
  )

  field(:clientFinish, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.HandshakeMessage.ClientFinish
  )
end

defmodule Amarula.Protocol.Proto.HistorySync do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:syncType, 1, type: Amarula.Protocol.Proto.HistorySync.HistorySyncType, enum: true)
  field(:conversations, 2, repeated: true, type: Amarula.Protocol.Proto.Conversation)
  field(:statusV3Messages, 3, repeated: true, type: Amarula.Protocol.Proto.WebMessageInfo)
  field(:chunkOrder, 5, proto3_optional: true, type: :uint32)
  field(:progress, 6, proto3_optional: true, type: :uint32)
  field(:pushnames, 7, repeated: true, type: Amarula.Protocol.Proto.Pushname)
  field(:globalSettings, 8, proto3_optional: true, type: Amarula.Protocol.Proto.GlobalSettings)
  field(:threadIdUserSecret, 9, proto3_optional: true, type: :bytes)
  field(:threadDsTimeframeOffset, 10, proto3_optional: true, type: :uint32)
  field(:recentStickers, 11, repeated: true, type: Amarula.Protocol.Proto.StickerMetadata)
  field(:pastParticipants, 12, repeated: true, type: Amarula.Protocol.Proto.PastParticipants)
  field(:callLogRecords, 13, repeated: true, type: Amarula.Protocol.Proto.CallLogRecord)

  field(:aiWaitListState, 14,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.HistorySync.BotAIWaitListState,
    enum: true
  )

  field(:phoneNumberToLidMappings, 15,
    repeated: true,
    type: Amarula.Protocol.Proto.PhoneNumberToLIDMapping
  )

  field(:companionMetaNonce, 16, proto3_optional: true, type: :string)
  field(:shareableChatIdentifierEncryptionKey, 17, proto3_optional: true, type: :bytes)
  field(:accounts, 18, repeated: true, type: Amarula.Protocol.Proto.Account)
end

defmodule Amarula.Protocol.Proto.HistorySyncMsg do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:message, 1, proto3_optional: true, type: Amarula.Protocol.Proto.WebMessageInfo)
  field(:msgOrderId, 2, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.HydratedTemplateButton.HydratedCallButton do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayText, 1, proto3_optional: true, type: :string)
  field(:phoneNumber, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.HydratedTemplateButton.HydratedQuickReplyButton do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayText, 1, proto3_optional: true, type: :string)
  field(:id, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.HydratedTemplateButton.HydratedURLButton do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayText, 1, proto3_optional: true, type: :string)
  field(:url, 2, proto3_optional: true, type: :string)
  field(:consentedUsersUrl, 3, proto3_optional: true, type: :string)

  field(:webviewPresentation, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.HydratedTemplateButton.HydratedURLButton.WebviewPresentationType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.HydratedTemplateButton do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:hydratedButton, 0)

  field(:index, 4, proto3_optional: true, type: :uint32)

  field(:quickReplyButton, 1,
    type: Amarula.Protocol.Proto.HydratedTemplateButton.HydratedQuickReplyButton,
    oneof: 0
  )

  field(:urlButton, 2,
    type: Amarula.Protocol.Proto.HydratedTemplateButton.HydratedURLButton,
    oneof: 0
  )

  field(:callButton, 3,
    type: Amarula.Protocol.Proto.HydratedTemplateButton.HydratedCallButton,
    oneof: 0
  )
end

defmodule Amarula.Protocol.Proto.IdentityKeyPairStructure do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:publicKey, 1, proto3_optional: true, type: :bytes)
  field(:privateKey, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.InThreadSurveyMetadata.InThreadSurveyOption do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:stringValue, 1, proto3_optional: true, type: :string)
  field(:numericValue, 2, proto3_optional: true, type: :uint32)
  field(:textTranslated, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.InThreadSurveyMetadata.InThreadSurveyPrivacyStatementPart do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:text, 1, proto3_optional: true, type: :string)
  field(:url, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.InThreadSurveyMetadata.InThreadSurveyQuestion do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:questionText, 1, proto3_optional: true, type: :string)
  field(:questionId, 2, proto3_optional: true, type: :string)

  field(:questionOptions, 3,
    repeated: true,
    type: Amarula.Protocol.Proto.InThreadSurveyMetadata.InThreadSurveyOption
  )
end

defmodule Amarula.Protocol.Proto.InThreadSurveyMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:tessaSessionId, 1, proto3_optional: true, type: :string)
  field(:simonSessionId, 2, proto3_optional: true, type: :string)
  field(:simonSurveyId, 3, proto3_optional: true, type: :string)
  field(:tessaRootId, 4, proto3_optional: true, type: :string)
  field(:requestId, 5, proto3_optional: true, type: :string)
  field(:tessaEvent, 6, proto3_optional: true, type: :string)
  field(:invitationHeaderText, 7, proto3_optional: true, type: :string)
  field(:invitationBodyText, 8, proto3_optional: true, type: :string)
  field(:invitationCtaText, 9, proto3_optional: true, type: :string)
  field(:invitationCtaUrl, 10, proto3_optional: true, type: :string)
  field(:surveyTitle, 11, proto3_optional: true, type: :string)

  field(:questions, 12,
    repeated: true,
    type: Amarula.Protocol.Proto.InThreadSurveyMetadata.InThreadSurveyQuestion
  )

  field(:surveyContinueButtonText, 13, proto3_optional: true, type: :string)
  field(:surveySubmitButtonText, 14, proto3_optional: true, type: :string)
  field(:privacyStatementFull, 15, proto3_optional: true, type: :string)

  field(:privacyStatementParts, 16,
    repeated: true,
    type: Amarula.Protocol.Proto.InThreadSurveyMetadata.InThreadSurveyPrivacyStatementPart
  )

  field(:feedbackToastText, 17, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.InteractiveAnnotation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:action, 0)

  field(:polygonVertices, 1, repeated: true, type: Amarula.Protocol.Proto.Point)
  field(:shouldSkipConfirmation, 4, proto3_optional: true, type: :bool)
  field(:embeddedContent, 5, proto3_optional: true, type: Amarula.Protocol.Proto.EmbeddedContent)

  field(:statusLinkType, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.InteractiveAnnotation.StatusLinkType,
    enum: true
  )

  field(:location, 2, type: Amarula.Protocol.Proto.Location, oneof: 0)

  field(:newsletter, 3,
    type: Amarula.Protocol.Proto.ContextInfo.ForwardedNewsletterMessageInfo,
    oneof: 0
  )

  field(:embeddedAction, 6, type: :bool, oneof: 0)
  field(:tapAction, 7, type: Amarula.Protocol.Proto.TapLinkAction, oneof: 0)
end

defmodule Amarula.Protocol.Proto.InteractiveMessageAdditionalMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isGalaxyFlowCompleted, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.KeepInChat do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:keepType, 1, proto3_optional: true, type: Amarula.Protocol.Proto.KeepType, enum: true)
  field(:serverTimestamp, 2, proto3_optional: true, type: :int64)
  field(:key, 3, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:deviceJid, 4, proto3_optional: true, type: :string)
  field(:clientTimestampMs, 5, proto3_optional: true, type: :int64)
  field(:serverTimestampMs, 6, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.KeyExchangeMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :uint32)
  field(:baseKey, 2, proto3_optional: true, type: :bytes)
  field(:ratchetKey, 3, proto3_optional: true, type: :bytes)
  field(:identityKey, 4, proto3_optional: true, type: :bytes)
  field(:baseKeySignature, 5, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.KeyId do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.LIDMigrationMapping do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:pn, 1, type: :uint64)
  field(:assignedLid, 2, type: :uint64)
  field(:latestLid, 3, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.LIDMigrationMappingSyncMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:encodedMappingPayload, 1, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.LIDMigrationMappingSyncPayload do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:pnToLidMappings, 1, repeated: true, type: Amarula.Protocol.Proto.LIDMigrationMapping)
  field(:chatDbMigrationTimestamp, 2, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.LegacyMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:eventResponseMessage, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.EventResponseMessage
  )

  field(:pollVote, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message.PollVoteMessage)
end

defmodule Amarula.Protocol.Proto.LimitSharing do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sharingLimited, 1, proto3_optional: true, type: :bool)

  field(:trigger, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.LimitSharing.TriggerType,
    enum: true
  )

  field(:limitSharingSettingTimestamp, 3, proto3_optional: true, type: :int64)
  field(:initiatedByMe, 4, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.LocalizedName do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:lg, 1, proto3_optional: true, type: :string)
  field(:lc, 2, proto3_optional: true, type: :string)
  field(:verifiedName, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Location do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:degreesLatitude, 1, proto3_optional: true, type: :double)
  field(:degreesLongitude, 2, proto3_optional: true, type: :double)
  field(:name, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.MediaData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:localPath, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.MediaNotifyMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:expressPathUrl, 1, proto3_optional: true, type: :string)
  field(:fileEncSha256, 2, proto3_optional: true, type: :bytes)
  field(:fileLength, 3, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.MediaRetryNotification do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:stanzaId, 1, proto3_optional: true, type: :string)
  field(:directPath, 2, proto3_optional: true, type: :string)

  field(:result, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MediaRetryNotification.ResultType,
    enum: true
  )

  field(:messageSecret, 4, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.MemberLabel do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:label, 1, proto3_optional: true, type: :string)
  field(:labelTimestamp, 2, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.AlbumMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:expectedImageCount, 2, proto3_optional: true, type: :uint32)
  field(:expectedVideoCount, 3, proto3_optional: true, type: :uint32)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.Message.AppStateFatalExceptionNotification do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:collectionNames, 1, repeated: true, type: :string)
  field(:timestamp, 2, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.AppStateSyncKey do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:keyId, 1, proto3_optional: true, type: Amarula.Protocol.Proto.Message.AppStateSyncKeyId)

  field(:keyData, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.AppStateSyncKeyData
  )
end

defmodule Amarula.Protocol.Proto.Message.AppStateSyncKeyData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:keyData, 1, proto3_optional: true, type: :bytes)

  field(:fingerprint, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.AppStateSyncKeyFingerprint
  )

  field(:timestamp, 3, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.AppStateSyncKeyFingerprint do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:rawId, 1, proto3_optional: true, type: :uint32)
  field(:currentIndex, 2, proto3_optional: true, type: :uint32)
  field(:deviceIndexes, 3, repeated: true, type: :uint32, packed: true, deprecated: false)
end

defmodule Amarula.Protocol.Proto.Message.AppStateSyncKeyId do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:keyId, 1, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Message.AppStateSyncKeyRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:keyIds, 1, repeated: true, type: Amarula.Protocol.Proto.Message.AppStateSyncKeyId)
end

defmodule Amarula.Protocol.Proto.Message.AppStateSyncKeyShare do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:keys, 1, repeated: true, type: Amarula.Protocol.Proto.Message.AppStateSyncKey)
end

defmodule Amarula.Protocol.Proto.Message.AudioMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:url, 1, proto3_optional: true, type: :string)
  field(:mimetype, 2, proto3_optional: true, type: :string)
  field(:fileSha256, 3, proto3_optional: true, type: :bytes)
  field(:fileLength, 4, proto3_optional: true, type: :uint64)
  field(:seconds, 5, proto3_optional: true, type: :uint32)
  field(:ptt, 6, proto3_optional: true, type: :bool)
  field(:mediaKey, 7, proto3_optional: true, type: :bytes)
  field(:fileEncSha256, 8, proto3_optional: true, type: :bytes)
  field(:directPath, 9, proto3_optional: true, type: :string)
  field(:mediaKeyTimestamp, 10, proto3_optional: true, type: :int64)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:streamingSidecar, 18, proto3_optional: true, type: :bytes)
  field(:waveform, 19, proto3_optional: true, type: :bytes)
  field(:backgroundArgb, 20, proto3_optional: true, type: :fixed32)
  field(:viewOnce, 21, proto3_optional: true, type: :bool)
  field(:accessibilityLabel, 22, proto3_optional: true, type: :string)

  field(:mediaKeyDomain, 23,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MediaKeyDomain,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.BCallMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sessionId, 1, proto3_optional: true, type: :string)

  field(:mediaType, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.BCallMessage.MediaType,
    enum: true
  )

  field(:masterKey, 3, proto3_optional: true, type: :bytes)
  field(:caption, 4, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ButtonsMessage.Button.ButtonText do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayText, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ButtonsMessage.Button.NativeFlowInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, proto3_optional: true, type: :string)
  field(:paramsJson, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ButtonsMessage.Button do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:buttonId, 1, proto3_optional: true, type: :string)

  field(:buttonText, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ButtonsMessage.Button.ButtonText
  )

  field(:type, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ButtonsMessage.Button.Type,
    enum: true
  )

  field(:nativeFlowInfo, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ButtonsMessage.Button.NativeFlowInfo
  )
end

defmodule Amarula.Protocol.Proto.Message.ButtonsMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:header, 0)

  field(:contentText, 6, proto3_optional: true, type: :string)
  field(:footerText, 7, proto3_optional: true, type: :string)
  field(:contextInfo, 8, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:buttons, 9, repeated: true, type: Amarula.Protocol.Proto.Message.ButtonsMessage.Button)

  field(:headerType, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ButtonsMessage.HeaderType,
    enum: true
  )

  field(:text, 1, type: :string, oneof: 0)
  field(:documentMessage, 2, type: Amarula.Protocol.Proto.Message.DocumentMessage, oneof: 0)
  field(:imageMessage, 3, type: Amarula.Protocol.Proto.Message.ImageMessage, oneof: 0)
  field(:videoMessage, 4, type: Amarula.Protocol.Proto.Message.VideoMessage, oneof: 0)
  field(:locationMessage, 5, type: Amarula.Protocol.Proto.Message.LocationMessage, oneof: 0)
end

defmodule Amarula.Protocol.Proto.Message.ButtonsResponseMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:response, 0)

  field(:selectedButtonId, 1, proto3_optional: true, type: :string)
  field(:contextInfo, 3, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)

  field(:type, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ButtonsResponseMessage.Type,
    enum: true
  )

  field(:selectedDisplayText, 2, type: :string, oneof: 0)
end

defmodule Amarula.Protocol.Proto.Message.Call do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:callKey, 1, proto3_optional: true, type: :bytes)
  field(:conversionSource, 2, proto3_optional: true, type: :string)
  field(:conversionData, 3, proto3_optional: true, type: :bytes)
  field(:conversionDelaySeconds, 4, proto3_optional: true, type: :uint32)
  field(:ctwaSignals, 5, proto3_optional: true, type: :string)
  field(:ctwaPayload, 6, proto3_optional: true, type: :bytes)
  field(:contextInfo, 7, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:nativeFlowCallButtonPayload, 8, proto3_optional: true, type: :string)
  field(:deeplinkPayload, 9, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.CallLogMessage.CallParticipant do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:jid, 1, proto3_optional: true, type: :string)

  field(:callOutcome, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.CallLogMessage.CallOutcome,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.CallLogMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isVideo, 1, proto3_optional: true, type: :bool)

  field(:callOutcome, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.CallLogMessage.CallOutcome,
    enum: true
  )

  field(:durationSecs, 3, proto3_optional: true, type: :int64)

  field(:callType, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.CallLogMessage.CallType,
    enum: true
  )

  field(:participants, 5,
    repeated: true,
    type: Amarula.Protocol.Proto.Message.CallLogMessage.CallParticipant
  )
end

defmodule Amarula.Protocol.Proto.Message.CancelPaymentRequestMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
end

defmodule Amarula.Protocol.Proto.Message.Chat do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayName, 1, proto3_optional: true, type: :string)
  field(:id, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.CloudAPIThreadControlNotification.CloudAPIThreadControlNotificationContent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:handoffNotificationText, 1, proto3_optional: true, type: :string)
  field(:extraJson, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.CloudAPIThreadControlNotification do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:status, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.CloudAPIThreadControlNotification.CloudAPIThreadControl,
    enum: true
  )

  field(:senderNotificationTimestampMs, 2, proto3_optional: true, type: :int64)
  field(:consumerLid, 3, proto3_optional: true, type: :string)
  field(:consumerPhoneNumber, 4, proto3_optional: true, type: :string)

  field(:notificationContent, 5,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.CloudAPIThreadControlNotification.CloudAPIThreadControlNotificationContent
  )

  field(:shouldSuppressNotification, 6, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.Message.CommentMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:message, 1, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:targetMessageKey, 2, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
end

defmodule Amarula.Protocol.Proto.Message.ContactMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayName, 1, proto3_optional: true, type: :string)
  field(:vcard, 16, proto3_optional: true, type: :string)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.Message.ContactsArrayMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayName, 1, proto3_optional: true, type: :string)
  field(:contacts, 2, repeated: true, type: Amarula.Protocol.Proto.Message.ContactMessage)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.Message.DeclinePaymentRequestMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
end

defmodule Amarula.Protocol.Proto.Message.DeviceSentMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:destinationJid, 1, proto3_optional: true, type: :string)
  field(:message, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:phash, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.DocumentMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:url, 1, proto3_optional: true, type: :string)
  field(:mimetype, 2, proto3_optional: true, type: :string)
  field(:title, 3, proto3_optional: true, type: :string)
  field(:fileSha256, 4, proto3_optional: true, type: :bytes)
  field(:fileLength, 5, proto3_optional: true, type: :uint64)
  field(:pageCount, 6, proto3_optional: true, type: :uint32)
  field(:mediaKey, 7, proto3_optional: true, type: :bytes)
  field(:fileName, 8, proto3_optional: true, type: :string)
  field(:fileEncSha256, 9, proto3_optional: true, type: :bytes)
  field(:directPath, 10, proto3_optional: true, type: :string)
  field(:mediaKeyTimestamp, 11, proto3_optional: true, type: :int64)
  field(:contactVcard, 12, proto3_optional: true, type: :bool)
  field(:thumbnailDirectPath, 13, proto3_optional: true, type: :string)
  field(:thumbnailSha256, 14, proto3_optional: true, type: :bytes)
  field(:thumbnailEncSha256, 15, proto3_optional: true, type: :bytes)
  field(:jpegThumbnail, 16, proto3_optional: true, type: :bytes)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:thumbnailHeight, 18, proto3_optional: true, type: :uint32)
  field(:thumbnailWidth, 19, proto3_optional: true, type: :uint32)
  field(:caption, 20, proto3_optional: true, type: :string)
  field(:accessibilityLabel, 21, proto3_optional: true, type: :string)

  field(:mediaKeyDomain, 22,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MediaKeyDomain,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.EncCommentMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:targetMessageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:encPayload, 2, proto3_optional: true, type: :bytes)
  field(:encIv, 3, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Message.EncEventResponseMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:eventCreationMessageKey, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageKey
  )

  field(:encPayload, 2, proto3_optional: true, type: :bytes)
  field(:encIv, 3, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Message.EncReactionMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:targetMessageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:encPayload, 2, proto3_optional: true, type: :bytes)
  field(:encIv, 3, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Message.EventMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:contextInfo, 1, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:isCanceled, 2, proto3_optional: true, type: :bool)
  field(:name, 3, proto3_optional: true, type: :string)
  field(:description, 4, proto3_optional: true, type: :string)
  field(:location, 5, proto3_optional: true, type: Amarula.Protocol.Proto.Message.LocationMessage)
  field(:joinLink, 6, proto3_optional: true, type: :string)
  field(:startTime, 7, proto3_optional: true, type: :int64)
  field(:endTime, 8, proto3_optional: true, type: :int64)
  field(:extraGuestsAllowed, 9, proto3_optional: true, type: :bool)
  field(:isScheduleCall, 10, proto3_optional: true, type: :bool)
  field(:hasReminder, 11, proto3_optional: true, type: :bool)
  field(:reminderOffsetSec, 12, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.EventResponseMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:response, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.EventResponseMessage.EventResponseType,
    enum: true
  )

  field(:timestampMs, 2, proto3_optional: true, type: :int64)
  field(:extraGuestCount, 3, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.Message.ExtendedTextMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:text, 1, proto3_optional: true, type: :string)
  field(:matchedText, 2, proto3_optional: true, type: :string)
  field(:description, 5, proto3_optional: true, type: :string)
  field(:title, 6, proto3_optional: true, type: :string)
  field(:textArgb, 7, proto3_optional: true, type: :fixed32)
  field(:backgroundArgb, 8, proto3_optional: true, type: :fixed32)

  field(:font, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ExtendedTextMessage.FontType,
    enum: true
  )

  field(:previewType, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ExtendedTextMessage.PreviewType,
    enum: true
  )

  field(:jpegThumbnail, 16, proto3_optional: true, type: :bytes)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:doNotPlayInline, 18, proto3_optional: true, type: :bool)
  field(:thumbnailDirectPath, 19, proto3_optional: true, type: :string)
  field(:thumbnailSha256, 20, proto3_optional: true, type: :bytes)
  field(:thumbnailEncSha256, 21, proto3_optional: true, type: :bytes)
  field(:mediaKey, 22, proto3_optional: true, type: :bytes)
  field(:mediaKeyTimestamp, 23, proto3_optional: true, type: :int64)
  field(:thumbnailHeight, 24, proto3_optional: true, type: :uint32)
  field(:thumbnailWidth, 25, proto3_optional: true, type: :uint32)

  field(:inviteLinkGroupType, 26,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ExtendedTextMessage.InviteLinkGroupType,
    enum: true
  )

  field(:inviteLinkParentGroupSubjectV2, 27, proto3_optional: true, type: :string)
  field(:inviteLinkParentGroupThumbnailV2, 28, proto3_optional: true, type: :bytes)

  field(:inviteLinkGroupTypeV2, 29,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ExtendedTextMessage.InviteLinkGroupType,
    enum: true
  )

  field(:viewOnce, 30, proto3_optional: true, type: :bool)
  field(:videoHeight, 31, proto3_optional: true, type: :uint32)
  field(:videoWidth, 32, proto3_optional: true, type: :uint32)

  field(:faviconMMSMetadata, 33,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MMSThumbnailMetadata
  )

  field(:linkPreviewMetadata, 34,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.LinkPreviewMetadata
  )

  field(:paymentLinkMetadata, 35,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PaymentLinkMetadata
  )

  field(:endCardTiles, 36, repeated: true, type: Amarula.Protocol.Proto.Message.VideoEndCard)
  field(:videoContentUrl, 37, proto3_optional: true, type: :string)
  field(:musicMetadata, 38, proto3_optional: true, type: Amarula.Protocol.Proto.EmbeddedMusic)

  field(:paymentExtendedMetadata, 39,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PaymentExtendedMetadata
  )
end

defmodule Amarula.Protocol.Proto.Message.FullHistorySyncOnDemandRequestMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:requestId, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.FutureProofMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:message, 1, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
end

defmodule Amarula.Protocol.Proto.Message.GroupInviteMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:groupJid, 1, proto3_optional: true, type: :string)
  field(:inviteCode, 2, proto3_optional: true, type: :string)
  field(:inviteExpiration, 3, proto3_optional: true, type: :int64)
  field(:groupName, 4, proto3_optional: true, type: :string)
  field(:jpegThumbnail, 5, proto3_optional: true, type: :bytes)
  field(:caption, 6, proto3_optional: true, type: :string)
  field(:contextInfo, 7, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)

  field(:groupType, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.GroupInviteMessage.GroupType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMCurrency do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:currencyCode, 1, proto3_optional: true, type: :string)
  field(:amount1000, 2, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeComponent do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:dayOfWeek, 1,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeComponent.DayOfWeekType,
    enum: true
  )

  field(:year, 2, proto3_optional: true, type: :uint32)
  field(:month, 3, proto3_optional: true, type: :uint32)
  field(:dayOfMonth, 4, proto3_optional: true, type: :uint32)
  field(:hour, 5, proto3_optional: true, type: :uint32)
  field(:minute, 6, proto3_optional: true, type: :uint32)

  field(:calendar, 7,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeComponent.CalendarType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeUnixEpoch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:timestamp, 1, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:datetimeOneof, 0)

  field(:component, 1,
    type:
      Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeComponent,
    oneof: 0
  )

  field(:unixEpoch, 2,
    type:
      Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime.HSMDateTimeUnixEpoch,
    oneof: 0
  )
end

defmodule Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:paramOneof, 0)

  field(:default, 1, proto3_optional: true, type: :string)

  field(:currency, 2,
    type:
      Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMCurrency,
    oneof: 0
  )

  field(:dateTime, 3,
    type:
      Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter.HSMDateTime,
    oneof: 0
  )
end

defmodule Amarula.Protocol.Proto.Message.HighlyStructuredMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:namespace, 1, proto3_optional: true, type: :string)
  field(:elementName, 2, proto3_optional: true, type: :string)
  field(:params, 3, repeated: true, type: :string)
  field(:fallbackLg, 4, proto3_optional: true, type: :string)
  field(:fallbackLc, 5, proto3_optional: true, type: :string)

  field(:localizableParams, 6,
    repeated: true,
    type: Amarula.Protocol.Proto.Message.HighlyStructuredMessage.HSMLocalizableParameter
  )

  field(:deterministicLg, 7, proto3_optional: true, type: :string)
  field(:deterministicLc, 8, proto3_optional: true, type: :string)

  field(:hydratedHsm, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.TemplateMessage
  )
end

defmodule Amarula.Protocol.Proto.Message.HistorySyncMessageAccessStatus do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:completeAccessGranted, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.Message.HistorySyncNotification do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:fileSha256, 1, proto3_optional: true, type: :bytes)
  field(:fileLength, 2, proto3_optional: true, type: :uint64)
  field(:mediaKey, 3, proto3_optional: true, type: :bytes)
  field(:fileEncSha256, 4, proto3_optional: true, type: :bytes)
  field(:directPath, 5, proto3_optional: true, type: :string)

  field(:syncType, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HistorySyncType,
    enum: true
  )

  field(:chunkOrder, 7, proto3_optional: true, type: :uint32)
  field(:originalMessageId, 8, proto3_optional: true, type: :string)
  field(:progress, 9, proto3_optional: true, type: :uint32)
  field(:oldestMsgInChunkTimestampSec, 10, proto3_optional: true, type: :int64)
  field(:initialHistBootstrapInlinePayload, 11, proto3_optional: true, type: :bytes)
  field(:peerDataRequestSessionId, 12, proto3_optional: true, type: :string)

  field(:fullHistorySyncOnDemandRequestMetadata, 13,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FullHistorySyncOnDemandRequestMetadata
  )

  field(:encHandle, 14, proto3_optional: true, type: :string)

  field(:messageAccessStatus, 15,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HistorySyncMessageAccessStatus
  )
end

defmodule Amarula.Protocol.Proto.Message.ImageMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:url, 1, proto3_optional: true, type: :string)
  field(:mimetype, 2, proto3_optional: true, type: :string)
  field(:caption, 3, proto3_optional: true, type: :string)
  field(:fileSha256, 4, proto3_optional: true, type: :bytes)
  field(:fileLength, 5, proto3_optional: true, type: :uint64)
  field(:height, 6, proto3_optional: true, type: :uint32)
  field(:width, 7, proto3_optional: true, type: :uint32)
  field(:mediaKey, 8, proto3_optional: true, type: :bytes)
  field(:fileEncSha256, 9, proto3_optional: true, type: :bytes)

  field(:interactiveAnnotations, 10,
    repeated: true,
    type: Amarula.Protocol.Proto.InteractiveAnnotation
  )

  field(:directPath, 11, proto3_optional: true, type: :string)
  field(:mediaKeyTimestamp, 12, proto3_optional: true, type: :int64)
  field(:jpegThumbnail, 16, proto3_optional: true, type: :bytes)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:firstScanSidecar, 18, proto3_optional: true, type: :bytes)
  field(:firstScanLength, 19, proto3_optional: true, type: :uint32)
  field(:experimentGroupId, 20, proto3_optional: true, type: :uint32)
  field(:scansSidecar, 21, proto3_optional: true, type: :bytes)
  field(:scanLengths, 22, repeated: true, type: :uint32)
  field(:midQualityFileSha256, 23, proto3_optional: true, type: :bytes)
  field(:midQualityFileEncSha256, 24, proto3_optional: true, type: :bytes)
  field(:viewOnce, 25, proto3_optional: true, type: :bool)
  field(:thumbnailDirectPath, 26, proto3_optional: true, type: :string)
  field(:thumbnailSha256, 27, proto3_optional: true, type: :bytes)
  field(:thumbnailEncSha256, 28, proto3_optional: true, type: :bytes)
  field(:staticUrl, 29, proto3_optional: true, type: :string)
  field(:annotations, 30, repeated: true, type: Amarula.Protocol.Proto.InteractiveAnnotation)

  field(:imageSourceType, 31,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ImageMessage.ImageSourceType,
    enum: true
  )

  field(:accessibilityLabel, 32, proto3_optional: true, type: :string)

  field(:mediaKeyDomain, 33,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MediaKeyDomain,
    enum: true
  )

  field(:qrUrl, 34, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.InitialSecurityNotificationSettingSync do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:securityNotificationEnabled, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage.Body do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:text, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage.CarouselMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:cards, 1, repeated: true, type: Amarula.Protocol.Proto.Message.InteractiveMessage)
  field(:messageVersion, 2, proto3_optional: true, type: :int32)

  field(:carouselCardType, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage.CarouselMessage.CarouselCardType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage.CollectionMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:bizJid, 1, proto3_optional: true, type: :string)
  field(:id, 2, proto3_optional: true, type: :string)
  field(:messageVersion, 3, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage.Footer do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:media, 0)

  field(:text, 1, proto3_optional: true, type: :string)
  field(:hasMediaAttachment, 3, proto3_optional: true, type: :bool)
  field(:audioMessage, 2, type: Amarula.Protocol.Proto.Message.AudioMessage, oneof: 0)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage.Header do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:media, 0)

  field(:title, 1, proto3_optional: true, type: :string)
  field(:subtitle, 2, proto3_optional: true, type: :string)
  field(:hasMediaAttachment, 5, proto3_optional: true, type: :bool)
  field(:documentMessage, 3, type: Amarula.Protocol.Proto.Message.DocumentMessage, oneof: 0)
  field(:imageMessage, 4, type: Amarula.Protocol.Proto.Message.ImageMessage, oneof: 0)
  field(:jpegThumbnail, 6, type: :bytes, oneof: 0)
  field(:videoMessage, 7, type: Amarula.Protocol.Proto.Message.VideoMessage, oneof: 0)
  field(:locationMessage, 8, type: Amarula.Protocol.Proto.Message.LocationMessage, oneof: 0)
  field(:productMessage, 9, type: Amarula.Protocol.Proto.Message.ProductMessage, oneof: 0)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage.NativeFlowMessage.NativeFlowButton do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, proto3_optional: true, type: :string)
  field(:buttonParamsJson, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage.NativeFlowMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:buttons, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage.NativeFlowMessage.NativeFlowButton
  )

  field(:messageParamsJson, 2, proto3_optional: true, type: :string)
  field(:messageVersion, 3, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage.ShopMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :string)

  field(:surface, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage.ShopMessage.Surface,
    enum: true
  )

  field(:messageVersion, 3, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:interactiveMessage, 0)

  field(:header, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage.Header
  )

  field(:body, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage.Body
  )

  field(:footer, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage.Footer
  )

  field(:contextInfo, 15, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:urlTrackingMap, 16, proto3_optional: true, type: Amarula.Protocol.Proto.UrlTrackingMap)

  field(:shopStorefrontMessage, 4,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage.ShopMessage,
    oneof: 0
  )

  field(:collectionMessage, 5,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage.CollectionMessage,
    oneof: 0
  )

  field(:nativeFlowMessage, 6,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage.NativeFlowMessage,
    oneof: 0
  )

  field(:carouselMessage, 7,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage.CarouselMessage,
    oneof: 0
  )
end

defmodule Amarula.Protocol.Proto.Message.InteractiveResponseMessage.Body do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:text, 1, proto3_optional: true, type: :string)

  field(:format, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InteractiveResponseMessage.Body.Format,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.InteractiveResponseMessage.NativeFlowResponseMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, proto3_optional: true, type: :string)
  field(:paramsJson, 2, proto3_optional: true, type: :string)
  field(:version, 3, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.Message.InteractiveResponseMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:interactiveResponseMessage, 0)

  field(:body, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InteractiveResponseMessage.Body
  )

  field(:contextInfo, 15, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)

  field(:nativeFlowResponseMessage, 2,
    type: Amarula.Protocol.Proto.Message.InteractiveResponseMessage.NativeFlowResponseMessage,
    oneof: 0
  )
end

defmodule Amarula.Protocol.Proto.Message.InvoiceMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:note, 1, proto3_optional: true, type: :string)
  field(:token, 2, proto3_optional: true, type: :string)

  field(:attachmentType, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InvoiceMessage.AttachmentType,
    enum: true
  )

  field(:attachmentMimetype, 4, proto3_optional: true, type: :string)
  field(:attachmentMediaKey, 5, proto3_optional: true, type: :bytes)
  field(:attachmentMediaKeyTimestamp, 6, proto3_optional: true, type: :int64)
  field(:attachmentFileSha256, 7, proto3_optional: true, type: :bytes)
  field(:attachmentFileEncSha256, 8, proto3_optional: true, type: :bytes)
  field(:attachmentDirectPath, 9, proto3_optional: true, type: :string)
  field(:attachmentJpegThumbnail, 10, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Message.KeepInChatMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:keepType, 2, proto3_optional: true, type: Amarula.Protocol.Proto.KeepType, enum: true)
  field(:timestampMs, 3, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.LinkPreviewMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:paymentLinkMetadata, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PaymentLinkMetadata
  )

  field(:urlMetadata, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message.URLMetadata)
  field(:fbExperimentId, 3, proto3_optional: true, type: :uint32)
  field(:linkMediaDuration, 4, proto3_optional: true, type: :uint32)

  field(:socialMediaPostType, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.LinkPreviewMetadata.SocialMediaPostType,
    enum: true
  )

  field(:linkInlineVideoMuted, 6, proto3_optional: true, type: :bool)
  field(:videoContentUrl, 7, proto3_optional: true, type: :string)
  field(:musicMetadata, 8, proto3_optional: true, type: Amarula.Protocol.Proto.EmbeddedMusic)
  field(:videoContentCaption, 9, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ListMessage.Product do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:productId, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ListMessage.ProductListHeaderImage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:productId, 1, proto3_optional: true, type: :string)
  field(:jpegThumbnail, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Message.ListMessage.ProductListInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:productSections, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.Message.ListMessage.ProductSection
  )

  field(:headerImage, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ListMessage.ProductListHeaderImage
  )

  field(:businessOwnerJid, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ListMessage.ProductSection do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, proto3_optional: true, type: :string)
  field(:products, 2, repeated: true, type: Amarula.Protocol.Proto.Message.ListMessage.Product)
end

defmodule Amarula.Protocol.Proto.Message.ListMessage.Row do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, proto3_optional: true, type: :string)
  field(:description, 2, proto3_optional: true, type: :string)
  field(:rowId, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ListMessage.Section do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, proto3_optional: true, type: :string)
  field(:rows, 2, repeated: true, type: Amarula.Protocol.Proto.Message.ListMessage.Row)
end

defmodule Amarula.Protocol.Proto.Message.ListMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, proto3_optional: true, type: :string)
  field(:description, 2, proto3_optional: true, type: :string)
  field(:buttonText, 3, proto3_optional: true, type: :string)

  field(:listType, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ListMessage.ListType,
    enum: true
  )

  field(:sections, 5, repeated: true, type: Amarula.Protocol.Proto.Message.ListMessage.Section)

  field(:productListInfo, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ListMessage.ProductListInfo
  )

  field(:footerText, 7, proto3_optional: true, type: :string)
  field(:contextInfo, 8, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.Message.ListResponseMessage.SingleSelectReply do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:selectedRowId, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ListResponseMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, proto3_optional: true, type: :string)

  field(:listType, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ListResponseMessage.ListType,
    enum: true
  )

  field(:singleSelectReply, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ListResponseMessage.SingleSelectReply
  )

  field(:contextInfo, 4, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:description, 5, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.LiveLocationMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:degreesLatitude, 1, proto3_optional: true, type: :double)
  field(:degreesLongitude, 2, proto3_optional: true, type: :double)
  field(:accuracyInMeters, 3, proto3_optional: true, type: :uint32)
  field(:speedInMps, 4, proto3_optional: true, type: :float)
  field(:degreesClockwiseFromMagneticNorth, 5, proto3_optional: true, type: :uint32)
  field(:caption, 6, proto3_optional: true, type: :string)
  field(:sequenceNumber, 7, proto3_optional: true, type: :int64)
  field(:timeOffset, 8, proto3_optional: true, type: :uint32)
  field(:jpegThumbnail, 16, proto3_optional: true, type: :bytes)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.Message.LocationMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:degreesLatitude, 1, proto3_optional: true, type: :double)
  field(:degreesLongitude, 2, proto3_optional: true, type: :double)
  field(:name, 3, proto3_optional: true, type: :string)
  field(:address, 4, proto3_optional: true, type: :string)
  field(:url, 5, proto3_optional: true, type: :string)
  field(:isLive, 6, proto3_optional: true, type: :bool)
  field(:accuracyInMeters, 7, proto3_optional: true, type: :uint32)
  field(:speedInMps, 8, proto3_optional: true, type: :float)
  field(:degreesClockwiseFromMagneticNorth, 9, proto3_optional: true, type: :uint32)
  field(:comment, 11, proto3_optional: true, type: :string)
  field(:jpegThumbnail, 16, proto3_optional: true, type: :bytes)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.Message.MMSThumbnailMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:thumbnailDirectPath, 1, proto3_optional: true, type: :string)
  field(:thumbnailSha256, 2, proto3_optional: true, type: :bytes)
  field(:thumbnailEncSha256, 3, proto3_optional: true, type: :bytes)
  field(:mediaKey, 4, proto3_optional: true, type: :bytes)
  field(:mediaKeyTimestamp, 5, proto3_optional: true, type: :int64)
  field(:thumbnailHeight, 6, proto3_optional: true, type: :uint32)
  field(:thumbnailWidth, 7, proto3_optional: true, type: :uint32)

  field(:mediaKeyDomain, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MediaKeyDomain,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.MessageHistoryBundle do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:mimetype, 1, proto3_optional: true, type: :string)
  field(:fileSha256, 2, proto3_optional: true, type: :bytes)
  field(:mediaKey, 3, proto3_optional: true, type: :bytes)
  field(:fileEncSha256, 4, proto3_optional: true, type: :bytes)
  field(:directPath, 5, proto3_optional: true, type: :string)
  field(:mediaKeyTimestamp, 6, proto3_optional: true, type: :int64)
  field(:contextInfo, 7, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)

  field(:messageHistoryMetadata, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MessageHistoryMetadata
  )
end

defmodule Amarula.Protocol.Proto.Message.MessageHistoryMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:historyReceivers, 1, repeated: true, type: :string)
  field(:oldestMessageTimestamp, 2, proto3_optional: true, type: :int64)
  field(:messageCount, 3, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.MessageHistoryNotice do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:contextInfo, 1, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)

  field(:messageHistoryMetadata, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MessageHistoryMetadata
  )
end

defmodule Amarula.Protocol.Proto.Message.NewsletterAdminInviteMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:newsletterJid, 1, proto3_optional: true, type: :string)
  field(:newsletterName, 2, proto3_optional: true, type: :string)
  field(:jpegThumbnail, 3, proto3_optional: true, type: :bytes)
  field(:caption, 4, proto3_optional: true, type: :string)
  field(:inviteExpiration, 5, proto3_optional: true, type: :int64)
  field(:contextInfo, 6, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.Message.NewsletterFollowerInviteMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:newsletterJid, 1, proto3_optional: true, type: :string)
  field(:newsletterName, 2, proto3_optional: true, type: :string)
  field(:jpegThumbnail, 3, proto3_optional: true, type: :bytes)
  field(:caption, 4, proto3_optional: true, type: :string)
  field(:contextInfo, 5, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.Message.OrderMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:orderId, 1, proto3_optional: true, type: :string)
  field(:thumbnail, 2, proto3_optional: true, type: :bytes)
  field(:itemCount, 3, proto3_optional: true, type: :int32)

  field(:status, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.OrderMessage.OrderStatus,
    enum: true
  )

  field(:surface, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.OrderMessage.OrderSurface,
    enum: true
  )

  field(:message, 6, proto3_optional: true, type: :string)
  field(:orderTitle, 7, proto3_optional: true, type: :string)
  field(:sellerJid, 8, proto3_optional: true, type: :string)
  field(:token, 9, proto3_optional: true, type: :string)
  field(:totalAmount1000, 10, proto3_optional: true, type: :int64)
  field(:totalCurrencyCode, 11, proto3_optional: true, type: :string)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:messageVersion, 12, proto3_optional: true, type: :int32)

  field(:orderRequestMessageId, 13,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageKey
  )

  field(:catalogType, 15, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PaymentExtendedMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1, proto3_optional: true, type: :uint32)
  field(:platform, 2, proto3_optional: true, type: :string)
  field(:messageParamsJson, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PaymentInviteMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:serviceType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PaymentInviteMessage.ServiceType,
    enum: true
  )

  field(:expiryTimestamp, 2, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.PaymentLinkMetadata.PaymentLinkButton do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayText, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PaymentLinkMetadata.PaymentLinkHeader do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:headerType, 1,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PaymentLinkMetadata.PaymentLinkHeader.PaymentLinkHeaderType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.PaymentLinkMetadata.PaymentLinkProvider do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:paramsJson, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PaymentLinkMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:button, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PaymentLinkMetadata.PaymentLinkButton
  )

  field(:header, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PaymentLinkMetadata.PaymentLinkHeader
  )

  field(:provider, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PaymentLinkMetadata.PaymentLinkProvider
  )
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.FullHistorySyncOnDemandRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:requestMetadata, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FullHistorySyncOnDemandRequestMetadata
  )

  field(:historySyncConfig, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceProps.HistorySyncConfig
  )
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.GalaxyFlowAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.GalaxyFlowAction.GalaxyFlowActionType,
    enum: true
  )

  field(:flowId, 2, proto3_optional: true, type: :string)
  field(:stanzaId, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.HistorySyncChunkRetryRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:syncType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HistorySyncType,
    enum: true
  )

  field(:chunkOrder, 2, proto3_optional: true, type: :uint32)
  field(:chunkNotificationId, 3, proto3_optional: true, type: :string)
  field(:regenerateChunk, 4, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.HistorySyncOnDemandRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:chatJid, 1, proto3_optional: true, type: :string)
  field(:oldestMsgId, 2, proto3_optional: true, type: :string)
  field(:oldestMsgFromMe, 3, proto3_optional: true, type: :bool)
  field(:onDemandMsgCount, 4, proto3_optional: true, type: :int32)
  field(:oldestMsgTimestampMs, 5, proto3_optional: true, type: :int64)
  field(:accountLid, 6, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.PlaceholderMessageResendRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.RequestStickerReupload do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:fileSha256, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.RequestUrlPreview do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:url, 1, proto3_optional: true, type: :string)
  field(:includeHqThumbnail, 2, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.SyncDCollectionFatalRecoveryRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:collectionName, 1, proto3_optional: true, type: :string)
  field(:timestamp, 2, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:peerDataOperationRequestType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PeerDataOperationRequestType,
    enum: true
  )

  field(:requestStickerReupload, 2,
    repeated: true,
    type: Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.RequestStickerReupload
  )

  field(:requestUrlPreview, 3,
    repeated: true,
    type: Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.RequestUrlPreview
  )

  field(:historySyncOnDemandRequest, 4,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.HistorySyncOnDemandRequest
  )

  field(:placeholderMessageResendRequest, 5,
    repeated: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.PlaceholderMessageResendRequest
  )

  field(:fullHistorySyncOnDemandRequest, 6,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.FullHistorySyncOnDemandRequest
  )

  field(:syncdCollectionFatalRecoveryRequest, 7,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.SyncDCollectionFatalRecoveryRequest
  )

  field(:historySyncChunkRetryRequest, 8,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.HistorySyncChunkRetryRequest
  )

  field(:galaxyFlowAction, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage.GalaxyFlowAction
  )
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.CompanionCanonicalUserNonceFetchResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:nonce, 1, proto3_optional: true, type: :string)
  field(:waFbid, 2, proto3_optional: true, type: :string)
  field(:forceRefresh, 3, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.CompanionMetaNonceFetchResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:nonce, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.FullHistorySyncOnDemandRequestResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:requestMetadata, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FullHistorySyncOnDemandRequestMetadata
  )

  field(:responseCode, 2,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.FullHistorySyncOnDemandResponseCode,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.HistorySyncChunkRetryResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:syncType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HistorySyncType,
    enum: true
  )

  field(:chunkOrder, 2, proto3_optional: true, type: :uint32)
  field(:requestId, 3, proto3_optional: true, type: :string)

  field(:responseCode, 4,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.HistorySyncChunkRetryResponseCode,
    enum: true
  )

  field(:canRecover, 5, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.LinkPreviewResponse.LinkPreviewHighQualityThumbnail do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:directPath, 1, proto3_optional: true, type: :string)
  field(:thumbHash, 2, proto3_optional: true, type: :string)
  field(:encThumbHash, 3, proto3_optional: true, type: :string)
  field(:mediaKey, 4, proto3_optional: true, type: :bytes)
  field(:mediaKeyTimestampMs, 5, proto3_optional: true, type: :int64)
  field(:thumbWidth, 6, proto3_optional: true, type: :int32)
  field(:thumbHeight, 7, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.LinkPreviewResponse.PaymentLinkPreviewMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isBusinessVerified, 1, proto3_optional: true, type: :bool)
  field(:providerName, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.LinkPreviewResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:url, 1, proto3_optional: true, type: :string)
  field(:title, 2, proto3_optional: true, type: :string)
  field(:description, 3, proto3_optional: true, type: :string)
  field(:thumbData, 4, proto3_optional: true, type: :bytes)
  field(:matchText, 6, proto3_optional: true, type: :string)
  field(:previewType, 7, proto3_optional: true, type: :string)

  field(:hqThumbnail, 8,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.LinkPreviewResponse.LinkPreviewHighQualityThumbnail
  )

  field(:previewMetadata, 9,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.LinkPreviewResponse.PaymentLinkPreviewMetadata
  )
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.PlaceholderMessageResendResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:webMessageInfoBytes, 1, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.SyncDSnapshotFatalRecoveryResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:collectionSnapshot, 1, proto3_optional: true, type: :bytes)
  field(:isCompressed, 2, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.WaffleNonceFetchResponse do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:nonce, 1, proto3_optional: true, type: :string)
  field(:waEntFbid, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:mediaUploadResult, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MediaRetryNotification.ResultType,
    enum: true
  )

  field(:stickerMessage, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StickerMessage
  )

  field(:linkPreviewResponse, 3,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.LinkPreviewResponse
  )

  field(:placeholderMessageResendResponse, 4,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.PlaceholderMessageResendResponse
  )

  field(:waffleNonceFetchRequestResponse, 5,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.WaffleNonceFetchResponse
  )

  field(:fullHistorySyncOnDemandRequestResponse, 6,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.FullHistorySyncOnDemandRequestResponse
  )

  field(:companionMetaNonceFetchRequestResponse, 7,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.CompanionMetaNonceFetchResponse
  )

  field(:syncdSnapshotFatalRecoveryResponse, 8,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.SyncDSnapshotFatalRecoveryResponse
  )

  field(:companionCanonicalUserNonceFetchRequestResponse, 9,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.CompanionCanonicalUserNonceFetchResponse
  )

  field(:historySyncChunkRetryResponse, 10,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult.HistorySyncChunkRetryResponse
  )
end

defmodule Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:peerDataOperationRequestType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PeerDataOperationRequestType,
    enum: true
  )

  field(:stanzaId, 2, proto3_optional: true, type: :string)

  field(:peerDataOperationResult, 3,
    repeated: true,
    type:
      Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage.PeerDataOperationResult
  )
end

defmodule Amarula.Protocol.Proto.Message.PinInChatMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)

  field(:type, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PinInChatMessage.Type,
    enum: true
  )

  field(:senderTimestampMs, 3, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.PlaceholderMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PlaceholderMessage.PlaceholderType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.PollCreationMessage.Option do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:optionName, 1, proto3_optional: true, type: :string)
  field(:optionHash, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.PollCreationMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:encKey, 1, proto3_optional: true, type: :bytes)
  field(:name, 2, proto3_optional: true, type: :string)

  field(:options, 3,
    repeated: true,
    type: Amarula.Protocol.Proto.Message.PollCreationMessage.Option
  )

  field(:selectableOptionsCount, 4, proto3_optional: true, type: :uint32)
  field(:contextInfo, 5, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)

  field(:pollContentType, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollContentType,
    enum: true
  )

  field(:pollType, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollType,
    enum: true
  )

  field(:correctAnswer, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollCreationMessage.Option
  )
end

defmodule Amarula.Protocol.Proto.Message.PollEncValue do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:encPayload, 1, proto3_optional: true, type: :bytes)
  field(:encIv, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Message.PollResultSnapshotMessage.PollVote do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:optionName, 1, proto3_optional: true, type: :string)
  field(:optionVoteCount, 2, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.PollResultSnapshotMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, proto3_optional: true, type: :string)

  field(:pollVotes, 2,
    repeated: true,
    type: Amarula.Protocol.Proto.Message.PollResultSnapshotMessage.PollVote
  )

  field(:contextInfo, 3, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)

  field(:pollType, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.PollUpdateMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:pollCreationMessageKey, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageKey
  )

  field(:vote, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message.PollEncValue)

  field(:metadata, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollUpdateMessageMetadata
  )

  field(:senderTimestampMs, 4, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.PollUpdateMessageMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3
end

defmodule Amarula.Protocol.Proto.Message.PollVoteMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:selectedOptions, 1, repeated: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Message.ProductMessage.CatalogSnapshot do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:catalogImage, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ImageMessage
  )

  field(:title, 2, proto3_optional: true, type: :string)
  field(:description, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ProductMessage.ProductSnapshot do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:productImage, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ImageMessage
  )

  field(:productId, 2, proto3_optional: true, type: :string)
  field(:title, 3, proto3_optional: true, type: :string)
  field(:description, 4, proto3_optional: true, type: :string)
  field(:currencyCode, 5, proto3_optional: true, type: :string)
  field(:priceAmount1000, 6, proto3_optional: true, type: :int64)
  field(:retailerId, 7, proto3_optional: true, type: :string)
  field(:url, 8, proto3_optional: true, type: :string)
  field(:productImageCount, 9, proto3_optional: true, type: :uint32)
  field(:firstImageId, 11, proto3_optional: true, type: :string)
  field(:salePriceAmount1000, 12, proto3_optional: true, type: :int64)
  field(:signedUrl, 13, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ProductMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:product, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ProductMessage.ProductSnapshot
  )

  field(:businessOwnerJid, 2, proto3_optional: true, type: :string)

  field(:catalog, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ProductMessage.CatalogSnapshot
  )

  field(:body, 5, proto3_optional: true, type: :string)
  field(:footer, 6, proto3_optional: true, type: :string)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.Message.ProtocolMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)

  field(:type, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ProtocolMessage.Type,
    enum: true
  )

  field(:ephemeralExpiration, 4, proto3_optional: true, type: :uint32)
  field(:ephemeralSettingTimestamp, 5, proto3_optional: true, type: :int64)

  field(:historySyncNotification, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HistorySyncNotification
  )

  field(:appStateSyncKeyShare, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.AppStateSyncKeyShare
  )

  field(:appStateSyncKeyRequest, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.AppStateSyncKeyRequest
  )

  field(:initialSecurityNotificationSettingSync, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InitialSecurityNotificationSettingSync
  )

  field(:appStateFatalExceptionNotification, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.AppStateFatalExceptionNotification
  )

  field(:disappearingMode, 11,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DisappearingMode
  )

  field(:editedMessage, 14, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:timestampMs, 15, proto3_optional: true, type: :int64)

  field(:peerDataOperationRequestMessage, 16,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PeerDataOperationRequestMessage
  )

  field(:peerDataOperationRequestResponseMessage, 17,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PeerDataOperationRequestResponseMessage
  )

  field(:botFeedbackMessage, 18,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.BotFeedbackMessage
  )

  field(:invokerJid, 19, proto3_optional: true, type: :string)

  field(:requestWelcomeMessageMetadata, 20,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.RequestWelcomeMessageMetadata
  )

  field(:mediaNotifyMessage, 21,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MediaNotifyMessage
  )

  field(:cloudApiThreadControlNotification, 22,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.CloudAPIThreadControlNotification
  )

  field(:lidMigrationMappingSyncMessage, 23,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.LIDMigrationMappingSyncMessage
  )

  field(:limitSharing, 24, proto3_optional: true, type: Amarula.Protocol.Proto.LimitSharing)
  field(:aiPsiMetadata, 25, proto3_optional: true, type: :bytes)
  field(:aiQueryFanout, 26, proto3_optional: true, type: Amarula.Protocol.Proto.AIQueryFanout)
  field(:memberLabel, 27, proto3_optional: true, type: Amarula.Protocol.Proto.MemberLabel)
end

defmodule Amarula.Protocol.Proto.Message.QuestionResponseMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:text, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ReactionMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:text, 2, proto3_optional: true, type: :string)
  field(:groupingKey, 3, proto3_optional: true, type: :string)
  field(:senderTimestampMs, 4, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.RequestPaymentMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:noteMessage, 4, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:currencyCodeIso4217, 1, proto3_optional: true, type: :string)
  field(:amount1000, 2, proto3_optional: true, type: :uint64)
  field(:requestFrom, 3, proto3_optional: true, type: :string)
  field(:expiryTimestamp, 5, proto3_optional: true, type: :int64)
  field(:amount, 6, proto3_optional: true, type: Amarula.Protocol.Proto.Money)
  field(:background, 7, proto3_optional: true, type: Amarula.Protocol.Proto.PaymentBackground)
end

defmodule Amarula.Protocol.Proto.Message.RequestPhoneNumberMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:contextInfo, 1, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
end

defmodule Amarula.Protocol.Proto.Message.RequestWelcomeMessageMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:localChatState, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.RequestWelcomeMessageMetadata.LocalChatState,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.ScheduledCallCreationMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:scheduledTimestampMs, 1, proto3_optional: true, type: :int64)

  field(:callType, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ScheduledCallCreationMessage.CallType,
    enum: true
  )

  field(:title, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.ScheduledCallEditMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)

  field(:editType, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ScheduledCallEditMessage.EditType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.SecretEncryptedMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:targetMessageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:encPayload, 2, proto3_optional: true, type: :bytes)
  field(:encIv, 3, proto3_optional: true, type: :bytes)

  field(:secretEncType, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.SecretEncryptedMessage.SecretEncType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.SendPaymentMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:noteMessage, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:requestMessageKey, 3, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:background, 4, proto3_optional: true, type: Amarula.Protocol.Proto.PaymentBackground)
  field(:transactionData, 5, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.SenderKeyDistributionMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:groupId, 1, proto3_optional: true, type: :string)
  field(:axolotlSenderKeyDistributionMessage, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Message.StatusNotificationMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:responseMessageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:originalMessageKey, 2, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)

  field(:type, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StatusNotificationMessage.StatusNotificationType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.StatusQuestionAnswerMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:text, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.StatusQuotedMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StatusQuotedMessage.StatusQuotedMessageType,
    enum: true
  )

  field(:text, 2, proto3_optional: true, type: :string)
  field(:thumbnail, 3, proto3_optional: true, type: :bytes)
  field(:originalStatusId, 4, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
end

defmodule Amarula.Protocol.Proto.Message.StatusStickerInteractionMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:stickerKey, 2, proto3_optional: true, type: :string)

  field(:type, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StatusStickerInteractionMessage.StatusStickerType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.StickerMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:url, 1, proto3_optional: true, type: :string)
  field(:fileSha256, 2, proto3_optional: true, type: :bytes)
  field(:fileEncSha256, 3, proto3_optional: true, type: :bytes)
  field(:mediaKey, 4, proto3_optional: true, type: :bytes)
  field(:mimetype, 5, proto3_optional: true, type: :string)
  field(:height, 6, proto3_optional: true, type: :uint32)
  field(:width, 7, proto3_optional: true, type: :uint32)
  field(:directPath, 8, proto3_optional: true, type: :string)
  field(:fileLength, 9, proto3_optional: true, type: :uint64)
  field(:mediaKeyTimestamp, 10, proto3_optional: true, type: :int64)
  field(:firstFrameLength, 11, proto3_optional: true, type: :uint32)
  field(:firstFrameSidecar, 12, proto3_optional: true, type: :bytes)
  field(:isAnimated, 13, proto3_optional: true, type: :bool)
  field(:pngThumbnail, 16, proto3_optional: true, type: :bytes)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:stickerSentTs, 18, proto3_optional: true, type: :int64)
  field(:isAvatar, 19, proto3_optional: true, type: :bool)
  field(:isAiSticker, 20, proto3_optional: true, type: :bool)
  field(:isLottie, 21, proto3_optional: true, type: :bool)
  field(:accessibilityLabel, 22, proto3_optional: true, type: :string)

  field(:mediaKeyDomain, 23,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MediaKeyDomain,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.StickerPackMessage.Sticker do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:fileName, 1, proto3_optional: true, type: :string)
  field(:isAnimated, 2, proto3_optional: true, type: :bool)
  field(:emojis, 3, repeated: true, type: :string)
  field(:accessibilityLabel, 4, proto3_optional: true, type: :string)
  field(:isLottie, 5, proto3_optional: true, type: :bool)
  field(:mimetype, 6, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.StickerPackMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:stickerPackId, 1, proto3_optional: true, type: :string)
  field(:name, 2, proto3_optional: true, type: :string)
  field(:publisher, 3, proto3_optional: true, type: :string)

  field(:stickers, 4,
    repeated: true,
    type: Amarula.Protocol.Proto.Message.StickerPackMessage.Sticker
  )

  field(:fileLength, 5, proto3_optional: true, type: :uint64)
  field(:fileSha256, 6, proto3_optional: true, type: :bytes)
  field(:fileEncSha256, 7, proto3_optional: true, type: :bytes)
  field(:mediaKey, 8, proto3_optional: true, type: :bytes)
  field(:directPath, 9, proto3_optional: true, type: :string)
  field(:caption, 10, proto3_optional: true, type: :string)
  field(:contextInfo, 11, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:packDescription, 12, proto3_optional: true, type: :string)
  field(:mediaKeyTimestamp, 13, proto3_optional: true, type: :int64)
  field(:trayIconFileName, 14, proto3_optional: true, type: :string)
  field(:thumbnailDirectPath, 15, proto3_optional: true, type: :string)
  field(:thumbnailSha256, 16, proto3_optional: true, type: :bytes)
  field(:thumbnailEncSha256, 17, proto3_optional: true, type: :bytes)
  field(:thumbnailHeight, 18, proto3_optional: true, type: :uint32)
  field(:thumbnailWidth, 19, proto3_optional: true, type: :uint32)
  field(:imageDataHash, 20, proto3_optional: true, type: :string)
  field(:stickerPackSize, 21, proto3_optional: true, type: :uint64)

  field(:stickerPackOrigin, 22,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StickerPackMessage.StickerPackOrigin,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message.StickerSyncRMRMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:filehash, 1, repeated: true, type: :string)
  field(:rmrSource, 2, proto3_optional: true, type: :string)
  field(:requestTimestamp, 3, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.Message.TemplateButtonReplyMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:selectedId, 1, proto3_optional: true, type: :string)
  field(:selectedDisplayText, 2, proto3_optional: true, type: :string)
  field(:contextInfo, 3, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:selectedIndex, 4, proto3_optional: true, type: :uint32)
  field(:selectedCarouselCardIndex, 5, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.Message.TemplateMessage.FourRowTemplate do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:title, 0)

  field(:content, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HighlyStructuredMessage
  )

  field(:footer, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HighlyStructuredMessage
  )

  field(:buttons, 8, repeated: true, type: Amarula.Protocol.Proto.TemplateButton)
  field(:documentMessage, 1, type: Amarula.Protocol.Proto.Message.DocumentMessage, oneof: 0)

  field(:highlyStructuredMessage, 2,
    type: Amarula.Protocol.Proto.Message.HighlyStructuredMessage,
    oneof: 0
  )

  field(:imageMessage, 3, type: Amarula.Protocol.Proto.Message.ImageMessage, oneof: 0)
  field(:videoMessage, 4, type: Amarula.Protocol.Proto.Message.VideoMessage, oneof: 0)
  field(:locationMessage, 5, type: Amarula.Protocol.Proto.Message.LocationMessage, oneof: 0)
end

defmodule Amarula.Protocol.Proto.Message.TemplateMessage.HydratedFourRowTemplate do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:title, 0)

  field(:hydratedContentText, 6, proto3_optional: true, type: :string)
  field(:hydratedFooterText, 7, proto3_optional: true, type: :string)
  field(:hydratedButtons, 8, repeated: true, type: Amarula.Protocol.Proto.HydratedTemplateButton)
  field(:templateId, 9, proto3_optional: true, type: :string)
  field(:maskLinkedDevices, 10, proto3_optional: true, type: :bool)
  field(:documentMessage, 1, type: Amarula.Protocol.Proto.Message.DocumentMessage, oneof: 0)
  field(:hydratedTitleText, 2, type: :string, oneof: 0)
  field(:imageMessage, 3, type: Amarula.Protocol.Proto.Message.ImageMessage, oneof: 0)
  field(:videoMessage, 4, type: Amarula.Protocol.Proto.Message.VideoMessage, oneof: 0)
  field(:locationMessage, 5, type: Amarula.Protocol.Proto.Message.LocationMessage, oneof: 0)
end

defmodule Amarula.Protocol.Proto.Message.TemplateMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:format, 0)

  field(:contextInfo, 3, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)

  field(:hydratedTemplate, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.TemplateMessage.HydratedFourRowTemplate
  )

  field(:templateId, 9, proto3_optional: true, type: :string)

  field(:fourRowTemplate, 1,
    type: Amarula.Protocol.Proto.Message.TemplateMessage.FourRowTemplate,
    oneof: 0
  )

  field(:hydratedFourRowTemplate, 2,
    type: Amarula.Protocol.Proto.Message.TemplateMessage.HydratedFourRowTemplate,
    oneof: 0
  )

  field(:interactiveMessageTemplate, 5,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage,
    oneof: 0
  )
end

defmodule Amarula.Protocol.Proto.Message.URLMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:fbExperimentId, 1, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.Message.VideoEndCard do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:username, 1, type: :string)
  field(:caption, 2, type: :string)
  field(:thumbnailImageUrl, 3, type: :string)
  field(:profilePictureUrl, 4, type: :string)
end

defmodule Amarula.Protocol.Proto.Message.VideoMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:url, 1, proto3_optional: true, type: :string)
  field(:mimetype, 2, proto3_optional: true, type: :string)
  field(:fileSha256, 3, proto3_optional: true, type: :bytes)
  field(:fileLength, 4, proto3_optional: true, type: :uint64)
  field(:seconds, 5, proto3_optional: true, type: :uint32)
  field(:mediaKey, 6, proto3_optional: true, type: :bytes)
  field(:caption, 7, proto3_optional: true, type: :string)
  field(:gifPlayback, 8, proto3_optional: true, type: :bool)
  field(:height, 9, proto3_optional: true, type: :uint32)
  field(:width, 10, proto3_optional: true, type: :uint32)
  field(:fileEncSha256, 11, proto3_optional: true, type: :bytes)

  field(:interactiveAnnotations, 12,
    repeated: true,
    type: Amarula.Protocol.Proto.InteractiveAnnotation
  )

  field(:directPath, 13, proto3_optional: true, type: :string)
  field(:mediaKeyTimestamp, 14, proto3_optional: true, type: :int64)
  field(:jpegThumbnail, 16, proto3_optional: true, type: :bytes)
  field(:contextInfo, 17, proto3_optional: true, type: Amarula.Protocol.Proto.ContextInfo)
  field(:streamingSidecar, 18, proto3_optional: true, type: :bytes)

  field(:gifAttribution, 19,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.VideoMessage.Attribution,
    enum: true
  )

  field(:viewOnce, 20, proto3_optional: true, type: :bool)
  field(:thumbnailDirectPath, 21, proto3_optional: true, type: :string)
  field(:thumbnailSha256, 22, proto3_optional: true, type: :bytes)
  field(:thumbnailEncSha256, 23, proto3_optional: true, type: :bytes)
  field(:staticUrl, 24, proto3_optional: true, type: :string)
  field(:annotations, 25, repeated: true, type: Amarula.Protocol.Proto.InteractiveAnnotation)
  field(:accessibilityLabel, 26, proto3_optional: true, type: :string)
  field(:processedVideos, 27, repeated: true, type: Amarula.Protocol.Proto.ProcessedVideo)
  field(:externalShareFullVideoDurationInSeconds, 28, proto3_optional: true, type: :uint32)
  field(:motionPhotoPresentationOffsetMs, 29, proto3_optional: true, type: :uint64)
  field(:metadataUrl, 30, proto3_optional: true, type: :string)

  field(:videoSourceType, 31,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.VideoMessage.VideoSourceType,
    enum: true
  )

  field(:mediaKeyDomain, 32,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MediaKeyDomain,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.Message do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:conversation, 1, proto3_optional: true, type: :string)

  field(:senderKeyDistributionMessage, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.SenderKeyDistributionMessage
  )

  field(:imageMessage, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ImageMessage
  )

  field(:contactMessage, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ContactMessage
  )

  field(:locationMessage, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.LocationMessage
  )

  field(:extendedTextMessage, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ExtendedTextMessage
  )

  field(:documentMessage, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.DocumentMessage
  )

  field(:audioMessage, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.AudioMessage
  )

  field(:videoMessage, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.VideoMessage
  )

  field(:call, 10, proto3_optional: true, type: Amarula.Protocol.Proto.Message.Call)
  field(:chat, 11, proto3_optional: true, type: Amarula.Protocol.Proto.Message.Chat)

  field(:protocolMessage, 12,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ProtocolMessage
  )

  field(:contactsArrayMessage, 13,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ContactsArrayMessage
  )

  field(:highlyStructuredMessage, 14,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HighlyStructuredMessage
  )

  field(:fastRatchetKeySenderKeyDistributionMessage, 15,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.SenderKeyDistributionMessage
  )

  field(:sendPaymentMessage, 16,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.SendPaymentMessage
  )

  field(:liveLocationMessage, 18,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.LiveLocationMessage
  )

  field(:requestPaymentMessage, 22,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.RequestPaymentMessage
  )

  field(:declinePaymentRequestMessage, 23,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.DeclinePaymentRequestMessage
  )

  field(:cancelPaymentRequestMessage, 24,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.CancelPaymentRequestMessage
  )

  field(:templateMessage, 25,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.TemplateMessage
  )

  field(:stickerMessage, 26,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StickerMessage
  )

  field(:groupInviteMessage, 28,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.GroupInviteMessage
  )

  field(:templateButtonReplyMessage, 29,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.TemplateButtonReplyMessage
  )

  field(:productMessage, 30,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ProductMessage
  )

  field(:deviceSentMessage, 31,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.DeviceSentMessage
  )

  field(:messageContextInfo, 35,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageContextInfo
  )

  field(:listMessage, 36, proto3_optional: true, type: Amarula.Protocol.Proto.Message.ListMessage)

  field(:viewOnceMessage, 37,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:orderMessage, 38,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.OrderMessage
  )

  field(:listResponseMessage, 39,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ListResponseMessage
  )

  field(:ephemeralMessage, 40,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:invoiceMessage, 41,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InvoiceMessage
  )

  field(:buttonsMessage, 42,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ButtonsMessage
  )

  field(:buttonsResponseMessage, 43,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ButtonsResponseMessage
  )

  field(:paymentInviteMessage, 44,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PaymentInviteMessage
  )

  field(:interactiveMessage, 45,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InteractiveMessage
  )

  field(:reactionMessage, 46,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ReactionMessage
  )

  field(:stickerSyncRmrMessage, 47,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StickerSyncRMRMessage
  )

  field(:interactiveResponseMessage, 48,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.InteractiveResponseMessage
  )

  field(:pollCreationMessage, 49,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollCreationMessage
  )

  field(:pollUpdateMessage, 50,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollUpdateMessage
  )

  field(:keepInChatMessage, 51,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.KeepInChatMessage
  )

  field(:documentWithCaptionMessage, 53,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:requestPhoneNumberMessage, 54,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.RequestPhoneNumberMessage
  )

  field(:viewOnceMessageV2, 55,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:encReactionMessage, 56,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.EncReactionMessage
  )

  field(:editedMessage, 58,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:viewOnceMessageV2Extension, 59,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:pollCreationMessageV2, 60,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollCreationMessage
  )

  field(:scheduledCallCreationMessage, 61,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ScheduledCallCreationMessage
  )

  field(:groupMentionedMessage, 62,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:pinInChatMessage, 63,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PinInChatMessage
  )

  field(:pollCreationMessageV3, 64,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollCreationMessage
  )

  field(:scheduledCallEditMessage, 65,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.ScheduledCallEditMessage
  )

  field(:ptvMessage, 66, proto3_optional: true, type: Amarula.Protocol.Proto.Message.VideoMessage)

  field(:botInvokeMessage, 67,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:callLogMesssage, 69,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.CallLogMessage
  )

  field(:messageHistoryBundle, 70,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MessageHistoryBundle
  )

  field(:encCommentMessage, 71,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.EncCommentMessage
  )

  field(:bcallMessage, 72,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.BCallMessage
  )

  field(:lottieStickerMessage, 74,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:eventMessage, 75,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.EventMessage
  )

  field(:encEventResponseMessage, 76,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.EncEventResponseMessage
  )

  field(:commentMessage, 77,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.CommentMessage
  )

  field(:newsletterAdminInviteMessage, 78,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.NewsletterAdminInviteMessage
  )

  field(:placeholderMessage, 80,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PlaceholderMessage
  )

  field(:secretEncryptedMessage, 82,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.SecretEncryptedMessage
  )

  field(:albumMessage, 83,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.AlbumMessage
  )

  field(:eventCoverImage, 85,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:stickerPackMessage, 86,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StickerPackMessage
  )

  field(:statusMentionMessage, 87,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:pollResultSnapshotMessage, 88,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollResultSnapshotMessage
  )

  field(:pollCreationOptionImageMessage, 90,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:associatedChildMessage, 91,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:groupStatusMentionMessage, 92,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:pollCreationMessageV4, 93,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:statusAddYours, 95,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:groupStatusMessage, 96,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:richResponseMessage, 97,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.AIRichResponseMessage
  )

  field(:statusNotificationMessage, 98,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StatusNotificationMessage
  )

  field(:limitSharingMessage, 99,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:botTaskMessage, 100,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:questionMessage, 101,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:messageHistoryNotice, 102,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.MessageHistoryNotice
  )

  field(:groupStatusMessageV2, 103,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:botForwardedMessage, 104,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:statusQuestionAnswerMessage, 105,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StatusQuestionAnswerMessage
  )

  field(:questionReplyMessage, 106,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.FutureProofMessage
  )

  field(:questionResponseMessage, 107,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.QuestionResponseMessage
  )

  field(:statusQuotedMessage, 109,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StatusQuotedMessage
  )

  field(:statusStickerInteractionMessage, 110,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.StatusStickerInteractionMessage
  )

  field(:pollCreationMessageV5, 111,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollCreationMessage
  )

  field(:newsletterFollowerInviteMessageV2, 113,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.NewsletterFollowerInviteMessage
  )

  field(:pollResultSnapshotMessageV3, 114,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.PollResultSnapshotMessage
  )
end

defmodule Amarula.Protocol.Proto.MessageAddOn do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageAddOnType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageAddOn.MessageAddOnType,
    enum: true
  )

  field(:messageAddOn, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:senderTimestampMs, 3, proto3_optional: true, type: :int64)
  field(:serverTimestampMs, 4, proto3_optional: true, type: :int64)

  field(:status, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebMessageInfo.Status,
    enum: true
  )

  field(:addOnContextInfo, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageAddOnContextInfo
  )

  field(:messageAddOnKey, 7, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:legacyMessage, 8, proto3_optional: true, type: Amarula.Protocol.Proto.LegacyMessage)
end

defmodule Amarula.Protocol.Proto.MessageAddOnContextInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageAddOnDurationInSecs, 1, proto3_optional: true, type: :uint32)

  field(:messageAddOnExpiryType, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageContextInfo.MessageAddonExpiryType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.MessageAssociation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:associationType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageAssociation.AssociationType,
    enum: true
  )

  field(:parentMessageKey, 2, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:messageIndex, 3, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.MessageContextInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:deviceListMetadata, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceListMetadata
  )

  field(:deviceListMetadataVersion, 2, proto3_optional: true, type: :int32)
  field(:messageSecret, 3, proto3_optional: true, type: :bytes)
  field(:paddingBytes, 4, proto3_optional: true, type: :bytes)
  field(:messageAddOnDurationInSecs, 5, proto3_optional: true, type: :uint32)
  field(:botMessageSecret, 6, proto3_optional: true, type: :bytes)
  field(:botMetadata, 7, proto3_optional: true, type: Amarula.Protocol.Proto.BotMetadata)
  field(:reportingTokenVersion, 8, proto3_optional: true, type: :int32)

  field(:messageAddOnExpiryType, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageContextInfo.MessageAddonExpiryType,
    enum: true
  )

  field(:messageAssociation, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageAssociation
  )

  field(:capiCreatedGroup, 11, proto3_optional: true, type: :bool)
  field(:supportPayload, 12, proto3_optional: true, type: :string)
  field(:limitSharing, 13, proto3_optional: true, type: Amarula.Protocol.Proto.LimitSharing)
  field(:limitSharingV2, 14, proto3_optional: true, type: Amarula.Protocol.Proto.LimitSharing)
  field(:threadId, 15, repeated: true, type: Amarula.Protocol.Proto.ThreadID)

  field(:weblinkRenderConfig, 16,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebLinkRenderConfig,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.MessageKey do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:remoteJid, 1, proto3_optional: true, type: :string)
  field(:fromMe, 2, proto3_optional: true, type: :bool)
  field(:id, 3, proto3_optional: true, type: :string)
  field(:participant, 4, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.MessageSecretMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:version, 1, proto3_optional: true, type: :sfixed32)
  field(:encIv, 2, proto3_optional: true, type: :bytes)
  field(:encPayload, 3, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.Money do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:value, 1, proto3_optional: true, type: :int64)
  field(:offset, 2, proto3_optional: true, type: :uint32)
  field(:currencyCode, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.MsgOpaqueData.EventLocation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:degreesLatitude, 1, proto3_optional: true, type: :double)
  field(:degreesLongitude, 2, proto3_optional: true, type: :double)
  field(:name, 3, proto3_optional: true, type: :string)
  field(:address, 4, proto3_optional: true, type: :string)
  field(:url, 5, proto3_optional: true, type: :string)
  field(:jpegThumbnail, 6, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.MsgOpaqueData.PollOption do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, proto3_optional: true, type: :string)
  field(:hash, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.MsgOpaqueData.PollVoteSnapshot do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:option, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MsgOpaqueData.PollOption)
  field(:optionVoteCount, 2, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.MsgOpaqueData.PollVotesSnapshot do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:pollVotes, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.MsgOpaqueData.PollVoteSnapshot
  )
end

defmodule Amarula.Protocol.Proto.MsgOpaqueData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:body, 1, proto3_optional: true, type: :string)
  field(:caption, 3, proto3_optional: true, type: :string)
  field(:lng, 5, proto3_optional: true, type: :double)
  field(:isLive, 6, proto3_optional: true, type: :bool)
  field(:lat, 7, proto3_optional: true, type: :double)
  field(:paymentAmount1000, 8, proto3_optional: true, type: :int32)
  field(:paymentNoteMsgBody, 9, proto3_optional: true, type: :string)
  field(:matchedText, 11, proto3_optional: true, type: :string)
  field(:title, 12, proto3_optional: true, type: :string)
  field(:description, 13, proto3_optional: true, type: :string)
  field(:futureproofBuffer, 14, proto3_optional: true, type: :bytes)
  field(:clientUrl, 15, proto3_optional: true, type: :string)
  field(:loc, 16, proto3_optional: true, type: :string)
  field(:pollName, 17, proto3_optional: true, type: :string)
  field(:pollOptions, 18, repeated: true, type: Amarula.Protocol.Proto.MsgOpaqueData.PollOption)
  field(:pollSelectableOptionsCount, 20, proto3_optional: true, type: :uint32)
  field(:messageSecret, 21, proto3_optional: true, type: :bytes)
  field(:originalSelfAuthor, 51, proto3_optional: true, type: :string)
  field(:senderTimestampMs, 22, proto3_optional: true, type: :int64)
  field(:pollUpdateParentKey, 23, proto3_optional: true, type: :string)
  field(:encPollVote, 24, proto3_optional: true, type: Amarula.Protocol.Proto.PollEncValue)
  field(:isSentCagPollCreation, 28, proto3_optional: true, type: :bool)

  field(:pollContentType, 42,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MsgOpaqueData.PollContentType,
    enum: true
  )

  field(:pollType, 46,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MsgOpaqueData.PollType,
    enum: true
  )

  field(:correctOptionIndex, 47, proto3_optional: true, type: :int32)

  field(:pollVotesSnapshot, 41,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MsgOpaqueData.PollVotesSnapshot
  )

  field(:encReactionTargetMessageKey, 25, proto3_optional: true, type: :string)
  field(:encReactionEncPayload, 26, proto3_optional: true, type: :bytes)
  field(:encReactionEncIv, 27, proto3_optional: true, type: :bytes)
  field(:botMessageSecret, 29, proto3_optional: true, type: :bytes)
  field(:targetMessageKey, 30, proto3_optional: true, type: :string)
  field(:encPayload, 31, proto3_optional: true, type: :bytes)
  field(:encIv, 32, proto3_optional: true, type: :bytes)
  field(:eventName, 33, proto3_optional: true, type: :string)
  field(:isEventCanceled, 34, proto3_optional: true, type: :bool)
  field(:eventDescription, 35, proto3_optional: true, type: :string)
  field(:eventJoinLink, 36, proto3_optional: true, type: :string)
  field(:eventStartTime, 37, proto3_optional: true, type: :int64)

  field(:eventLocation, 38,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MsgOpaqueData.EventLocation
  )

  field(:eventEndTime, 40, proto3_optional: true, type: :int64)
  field(:eventIsScheduledCall, 44, proto3_optional: true, type: :bool)
  field(:eventExtraGuestsAllowed, 45, proto3_optional: true, type: :bool)
  field(:plainProtobufBytes, 43, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.MsgRowOpaqueData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:currentMsg, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MsgOpaqueData)
  field(:quotedMsg, 2, proto3_optional: true, type: Amarula.Protocol.Proto.MsgOpaqueData)
end

defmodule Amarula.Protocol.Proto.NoiseCertificate.Details do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:serial, 1, proto3_optional: true, type: :uint32)
  field(:issuer, 2, proto3_optional: true, type: :string)
  field(:expires, 3, proto3_optional: true, type: :uint64)
  field(:subject, 4, proto3_optional: true, type: :string)
  field(:key, 5, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.NoiseCertificate do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:details, 1, proto3_optional: true, type: :bytes)
  field(:signature, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.NotificationMessageInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:message, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:messageTimestamp, 3, proto3_optional: true, type: :uint64)
  field(:participant, 4, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.NotificationSettings do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageVibrate, 1, proto3_optional: true, type: :string)
  field(:messagePopup, 2, proto3_optional: true, type: :string)
  field(:messageLight, 3, proto3_optional: true, type: :string)
  field(:lowPriorityNotifications, 4, proto3_optional: true, type: :bool)
  field(:reactionsMuted, 5, proto3_optional: true, type: :bool)
  field(:callVibrate, 6, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.PairingRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:companionPublicKey, 1, proto3_optional: true, type: :bytes)
  field(:companionIdentityKey, 2, proto3_optional: true, type: :bytes)
  field(:advSecret, 3, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.PastParticipant do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:userJid, 1, proto3_optional: true, type: :string)

  field(:leaveReason, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.PastParticipant.LeaveReason,
    enum: true
  )

  field(:leaveTs, 3, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.PastParticipants do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:groupJid, 1, proto3_optional: true, type: :string)
  field(:pastParticipants, 2, repeated: true, type: Amarula.Protocol.Proto.PastParticipant)
end

defmodule Amarula.Protocol.Proto.PatchDebugData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:currentLthash, 1, proto3_optional: true, type: :bytes)
  field(:newLthash, 2, proto3_optional: true, type: :bytes)
  field(:patchVersion, 3, proto3_optional: true, type: :bytes)
  field(:collectionName, 4, proto3_optional: true, type: :bytes)
  field(:firstFourBytesFromAHashOfSnapshotMacKey, 5, proto3_optional: true, type: :bytes)
  field(:newLthashSubtract, 6, proto3_optional: true, type: :bytes)
  field(:numberAdd, 7, proto3_optional: true, type: :int32)
  field(:numberRemove, 8, proto3_optional: true, type: :int32)
  field(:numberOverride, 9, proto3_optional: true, type: :int32)

  field(:senderPlatform, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.PatchDebugData.Platform,
    enum: true
  )

  field(:isSenderPrimary, 11, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.PaymentBackground.MediaData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:mediaKey, 1, proto3_optional: true, type: :bytes)
  field(:mediaKeyTimestamp, 2, proto3_optional: true, type: :int64)
  field(:fileSha256, 3, proto3_optional: true, type: :bytes)
  field(:fileEncSha256, 4, proto3_optional: true, type: :bytes)
  field(:directPath, 5, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.PaymentBackground do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :string)
  field(:fileLength, 2, proto3_optional: true, type: :uint64)
  field(:width, 3, proto3_optional: true, type: :uint32)
  field(:height, 4, proto3_optional: true, type: :uint32)
  field(:mimetype, 5, proto3_optional: true, type: :string)
  field(:placeholderArgb, 6, proto3_optional: true, type: :fixed32)
  field(:textArgb, 7, proto3_optional: true, type: :fixed32)
  field(:subtextArgb, 8, proto3_optional: true, type: :fixed32)

  field(:mediaData, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.PaymentBackground.MediaData
  )

  field(:type, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.PaymentBackground.Type,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.PaymentInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:currencyDeprecated, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.PaymentInfo.Currency,
    enum: true
  )

  field(:amount1000, 2, proto3_optional: true, type: :uint64)
  field(:receiverJid, 3, proto3_optional: true, type: :string)

  field(:status, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.PaymentInfo.Status,
    enum: true
  )

  field(:transactionTimestamp, 5, proto3_optional: true, type: :uint64)
  field(:requestMessageKey, 6, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:expiryTimestamp, 7, proto3_optional: true, type: :uint64)
  field(:futureproofed, 8, proto3_optional: true, type: :bool)
  field(:currency, 9, proto3_optional: true, type: :string)

  field(:txnStatus, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.PaymentInfo.TxnStatus,
    enum: true
  )

  field(:useNoviFiatFormat, 11, proto3_optional: true, type: :bool)
  field(:primaryAmount, 12, proto3_optional: true, type: Amarula.Protocol.Proto.Money)
  field(:exchangeAmount, 13, proto3_optional: true, type: Amarula.Protocol.Proto.Money)
end

defmodule Amarula.Protocol.Proto.PhoneNumberToLIDMapping do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:pnJid, 1, proto3_optional: true, type: :string)
  field(:lidJid, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.PhotoChange do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:oldPhoto, 1, proto3_optional: true, type: :bytes)
  field(:newPhoto, 2, proto3_optional: true, type: :bytes)
  field(:newPhotoId, 3, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.PinInChat do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1, proto3_optional: true, type: Amarula.Protocol.Proto.PinInChat.Type, enum: true)
  field(:key, 2, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:senderTimestampMs, 3, proto3_optional: true, type: :int64)
  field(:serverTimestampMs, 4, proto3_optional: true, type: :int64)

  field(:messageAddOnContextInfo, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.MessageAddOnContextInfo
  )
end

defmodule Amarula.Protocol.Proto.Point do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:xDeprecated, 1, proto3_optional: true, type: :int32)
  field(:yDeprecated, 2, proto3_optional: true, type: :int32)
  field(:x, 3, proto3_optional: true, type: :double)
  field(:y, 4, proto3_optional: true, type: :double)
end

defmodule Amarula.Protocol.Proto.PollAdditionalMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:pollInvalidated, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.PollEncValue do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:encPayload, 1, proto3_optional: true, type: :bytes)
  field(:encIv, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.PollUpdate do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:pollUpdateMessageKey, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:vote, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message.PollVoteMessage)
  field(:senderTimestampMs, 3, proto3_optional: true, type: :int64)
  field(:serverTimestampMs, 4, proto3_optional: true, type: :int64)
  field(:unread, 5, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.PreKeyRecordStructure do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :uint32)
  field(:publicKey, 2, proto3_optional: true, type: :bytes)
  field(:privateKey, 3, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.PreKeySignalMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:registrationId, 5, proto3_optional: true, type: :uint32)
  field(:preKeyId, 1, proto3_optional: true, type: :uint32)
  field(:signedPreKeyId, 6, proto3_optional: true, type: :uint32)
  field(:baseKey, 2, proto3_optional: true, type: :bytes)
  field(:identityKey, 3, proto3_optional: true, type: :bytes)
  field(:message, 4, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.PremiumMessageInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:serverCampaignId, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.PrimaryEphemeralIdentity do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:publicKey, 1, proto3_optional: true, type: :bytes)
  field(:nonce, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.ProcessedVideo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:directPath, 1, proto3_optional: true, type: :string)
  field(:fileSha256, 2, proto3_optional: true, type: :bytes)
  field(:height, 3, proto3_optional: true, type: :uint32)
  field(:width, 4, proto3_optional: true, type: :uint32)
  field(:fileLength, 5, proto3_optional: true, type: :uint64)
  field(:bitrate, 6, proto3_optional: true, type: :uint32)

  field(:quality, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ProcessedVideo.VideoQuality,
    enum: true
  )

  field(:capabilities, 8, repeated: true, type: :string)
end

defmodule Amarula.Protocol.Proto.ProloguePayload do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:companionEphemeralIdentity, 1, proto3_optional: true, type: :bytes)
  field(:commitment, 2, proto3_optional: true, type: Amarula.Protocol.Proto.CompanionCommitment)
end

defmodule Amarula.Protocol.Proto.Pushname do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :string)
  field(:pushname, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.QuarantinedMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:originalData, 1, proto3_optional: true, type: :bytes)
  field(:extractedText, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.Reaction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:text, 2, proto3_optional: true, type: :string)
  field(:groupingKey, 3, proto3_optional: true, type: :string)
  field(:senderTimestampMs, 4, proto3_optional: true, type: :int64)
  field(:unread, 5, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.RecentEmojiWeight do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:emoji, 1, proto3_optional: true, type: :string)
  field(:weight, 2, proto3_optional: true, type: :float)
end

defmodule Amarula.Protocol.Proto.RecordStructure do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:currentSession, 1, proto3_optional: true, type: Amarula.Protocol.Proto.SessionStructure)
  field(:previousSessions, 2, repeated: true, type: Amarula.Protocol.Proto.SessionStructure)
end

defmodule Amarula.Protocol.Proto.Reportable do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:minVersion, 1, proto3_optional: true, type: :uint32)
  field(:maxVersion, 2, proto3_optional: true, type: :uint32)
  field(:notReportableMinVersion, 3, proto3_optional: true, type: :uint32)
  field(:never, 4, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.ReportingTokenInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:reportingTag, 1, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SenderKeyDistributionMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :uint32)
  field(:iteration, 2, proto3_optional: true, type: :uint32)
  field(:chainKey, 3, proto3_optional: true, type: :bytes)
  field(:signingKey, 4, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SenderKeyMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :uint32)
  field(:iteration, 2, proto3_optional: true, type: :uint32)
  field(:ciphertext, 3, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SenderKeyRecordStructure do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:senderKeyStates, 1, repeated: true, type: Amarula.Protocol.Proto.SenderKeyStateStructure)
end

defmodule Amarula.Protocol.Proto.SenderKeyStateStructure.SenderChainKey do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:iteration, 1, proto3_optional: true, type: :uint32)
  field(:seed, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SenderKeyStateStructure.SenderMessageKey do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:iteration, 1, proto3_optional: true, type: :uint32)
  field(:seed, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SenderKeyStateStructure.SenderSigningKey do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:public, 1, proto3_optional: true, type: :bytes)
  field(:private, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SenderKeyStateStructure do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:senderKeyId, 1, proto3_optional: true, type: :uint32)

  field(:senderChainKey, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SenderKeyStateStructure.SenderChainKey
  )

  field(:senderSigningKey, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SenderKeyStateStructure.SenderSigningKey
  )

  field(:senderMessageKeys, 4,
    repeated: true,
    type: Amarula.Protocol.Proto.SenderKeyStateStructure.SenderMessageKey
  )
end

defmodule Amarula.Protocol.Proto.ServerErrorReceipt do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:stanzaId, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SessionStructure.Chain.ChainKey do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:index, 1, proto3_optional: true, type: :uint32)
  field(:key, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SessionStructure.Chain.MessageKey do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:index, 1, proto3_optional: true, type: :uint32)
  field(:cipherKey, 2, proto3_optional: true, type: :bytes)
  field(:macKey, 3, proto3_optional: true, type: :bytes)
  field(:iv, 4, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SessionStructure.Chain do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:senderRatchetKey, 1, proto3_optional: true, type: :bytes)
  field(:senderRatchetKeyPrivate, 2, proto3_optional: true, type: :bytes)

  field(:chainKey, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SessionStructure.Chain.ChainKey
  )

  field(:messageKeys, 4,
    repeated: true,
    type: Amarula.Protocol.Proto.SessionStructure.Chain.MessageKey
  )
end

defmodule Amarula.Protocol.Proto.SessionStructure.PendingKeyExchange do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sequence, 1, proto3_optional: true, type: :uint32)
  field(:localBaseKey, 2, proto3_optional: true, type: :bytes)
  field(:localBaseKeyPrivate, 3, proto3_optional: true, type: :bytes)
  field(:localRatchetKey, 4, proto3_optional: true, type: :bytes)
  field(:localRatchetKeyPrivate, 5, proto3_optional: true, type: :bytes)
  field(:localIdentityKey, 7, proto3_optional: true, type: :bytes)
  field(:localIdentityKeyPrivate, 8, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SessionStructure.PendingPreKey do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:preKeyId, 1, proto3_optional: true, type: :uint32)
  field(:signedPreKeyId, 3, proto3_optional: true, type: :int32)
  field(:baseKey, 2, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SessionStructure do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sessionVersion, 1, proto3_optional: true, type: :uint32)
  field(:localIdentityPublic, 2, proto3_optional: true, type: :bytes)
  field(:remoteIdentityPublic, 3, proto3_optional: true, type: :bytes)
  field(:rootKey, 4, proto3_optional: true, type: :bytes)
  field(:previousCounter, 5, proto3_optional: true, type: :uint32)

  field(:senderChain, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SessionStructure.Chain
  )

  field(:receiverChains, 7, repeated: true, type: Amarula.Protocol.Proto.SessionStructure.Chain)

  field(:pendingKeyExchange, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SessionStructure.PendingKeyExchange
  )

  field(:pendingPreKey, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SessionStructure.PendingPreKey
  )

  field(:remoteRegistrationId, 10, proto3_optional: true, type: :uint32)
  field(:localRegistrationId, 11, proto3_optional: true, type: :uint32)
  field(:needsRefresh, 12, proto3_optional: true, type: :bool)
  field(:aliceBaseKey, 13, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SessionTransparencyMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:disclaimerText, 1, proto3_optional: true, type: :string)
  field(:hcaId, 2, proto3_optional: true, type: :string)

  field(:sessionTransparencyType, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SessionTransparencyType,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.SignalMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:ratchetKey, 1, proto3_optional: true, type: :bytes)
  field(:counter, 2, proto3_optional: true, type: :uint32)
  field(:previousCounter, 3, proto3_optional: true, type: :uint32)
  field(:ciphertext, 4, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SignedPreKeyRecordStructure do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :uint32)
  field(:publicKey, 2, proto3_optional: true, type: :bytes)
  field(:privateKey, 3, proto3_optional: true, type: :bytes)
  field(:signature, 4, proto3_optional: true, type: :bytes)
  field(:timestamp, 5, proto3_optional: true, type: :fixed64)
end

defmodule Amarula.Protocol.Proto.StatusAttribution.AiCreatedAttribution do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:source, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.StatusAttribution.AiCreatedAttribution.Source,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.StatusAttribution.ExternalShare do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:actionUrl, 1, proto3_optional: true, type: :string)

  field(:source, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.StatusAttribution.ExternalShare.Source,
    enum: true
  )

  field(:duration, 3, proto3_optional: true, type: :int32)
  field(:actionFallbackUrl, 4, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.StatusAttribution.GroupStatus do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:authorJid, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.StatusAttribution.Music do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:authorName, 1, proto3_optional: true, type: :string)
  field(:songId, 2, proto3_optional: true, type: :string)
  field(:title, 3, proto3_optional: true, type: :string)
  field(:author, 4, proto3_optional: true, type: :string)
  field(:artistAttribution, 5, proto3_optional: true, type: :string)
  field(:isExplicit, 6, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.StatusAttribution.RLAttribution do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:source, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.StatusAttribution.RLAttribution.Source,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.StatusAttribution.StatusReshare.Metadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:duration, 1, proto3_optional: true, type: :int32)
  field(:channelJid, 2, proto3_optional: true, type: :string)
  field(:channelMessageId, 3, proto3_optional: true, type: :int32)
  field(:hasMultipleReshares, 4, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.StatusAttribution.StatusReshare do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:source, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.StatusAttribution.StatusReshare.Source,
    enum: true
  )

  field(:metadata, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.StatusAttribution.StatusReshare.Metadata
  )
end

defmodule Amarula.Protocol.Proto.StatusAttribution do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:attributionData, 0)

  field(:type, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.StatusAttribution.Type,
    enum: true
  )

  field(:actionUrl, 2, proto3_optional: true, type: :string)
  field(:statusReshare, 3, type: Amarula.Protocol.Proto.StatusAttribution.StatusReshare, oneof: 0)
  field(:externalShare, 4, type: Amarula.Protocol.Proto.StatusAttribution.ExternalShare, oneof: 0)
  field(:music, 5, type: Amarula.Protocol.Proto.StatusAttribution.Music, oneof: 0)
  field(:groupStatus, 6, type: Amarula.Protocol.Proto.StatusAttribution.GroupStatus, oneof: 0)
  field(:rlAttribution, 7, type: Amarula.Protocol.Proto.StatusAttribution.RLAttribution, oneof: 0)

  field(:aiCreatedAttribution, 8,
    type: Amarula.Protocol.Proto.StatusAttribution.AiCreatedAttribution,
    oneof: 0
  )
end

defmodule Amarula.Protocol.Proto.StatusMentionMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:quotedStatus, 1, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
end

defmodule Amarula.Protocol.Proto.StatusPSA do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:campaignId, 44, type: :uint64)
  field(:campaignExpirationTimestamp, 45, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.StickerMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:url, 1, proto3_optional: true, type: :string)
  field(:fileSha256, 2, proto3_optional: true, type: :bytes)
  field(:fileEncSha256, 3, proto3_optional: true, type: :bytes)
  field(:mediaKey, 4, proto3_optional: true, type: :bytes)
  field(:mimetype, 5, proto3_optional: true, type: :string)
  field(:height, 6, proto3_optional: true, type: :uint32)
  field(:width, 7, proto3_optional: true, type: :uint32)
  field(:directPath, 8, proto3_optional: true, type: :string)
  field(:fileLength, 9, proto3_optional: true, type: :uint64)
  field(:weight, 10, proto3_optional: true, type: :float)
  field(:lastStickerSentTs, 11, proto3_optional: true, type: :int64)
  field(:isLottie, 12, proto3_optional: true, type: :bool)
  field(:imageHash, 13, proto3_optional: true, type: :string)
  field(:isAvatarSticker, 14, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionData do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:index, 1, proto3_optional: true, type: :bytes)
  field(:value, 2, proto3_optional: true, type: Amarula.Protocol.Proto.SyncActionValue)
  field(:padding, 3, proto3_optional: true, type: :bytes)
  field(:version, 4, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.AgentAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, proto3_optional: true, type: :string)
  field(:deviceID, 2, proto3_optional: true, type: :int32)
  field(:isDeleted, 3, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.AiThreadRenameAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:newTitle, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.AndroidUnsupportedActions do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:allowed, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.ArchiveChatAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:archived, 1, proto3_optional: true, type: :bool)

  field(:messageRange, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.SyncActionMessageRange
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.AvatarUpdatedAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:eventType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.AvatarUpdatedAction.AvatarEventType,
    enum: true
  )

  field(:recentAvatarStickers, 2,
    repeated: true,
    type: Amarula.Protocol.Proto.SyncActionValue.StickerAction
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.BotWelcomeRequestAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isSent, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.BroadcastListParticipant do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:lidJid, 1, type: :string)
  field(:pnJid, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.BusinessBroadcastAssociationAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:deleted, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.BusinessBroadcastListAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:deleted, 1, proto3_optional: true, type: :bool)

  field(:participants, 2,
    repeated: true,
    type: Amarula.Protocol.Proto.SyncActionValue.BroadcastListParticipant
  )

  field(:listName, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.CallLogAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:callLogRecord, 1, proto3_optional: true, type: Amarula.Protocol.Proto.CallLogRecord)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.ChatAssignmentAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:deviceAgentID, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.ChatAssignmentOpenedStatusAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:chatOpened, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.ClearChatAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageRange, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.SyncActionMessageRange
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.ContactAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:fullName, 1, proto3_optional: true, type: :string)
  field(:firstName, 2, proto3_optional: true, type: :string)
  field(:lidJid, 3, proto3_optional: true, type: :string)
  field(:saveOnPrimaryAddressbook, 4, proto3_optional: true, type: :bool)
  field(:pnJid, 5, proto3_optional: true, type: :string)
  field(:username, 6, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.CtwaPerCustomerDataSharingAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isCtwaPerCustomerDataSharingEnabled, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.CustomPaymentMethod do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:credentialId, 1, type: :string)
  field(:country, 2, type: :string)
  field(:type, 3, type: :string)

  field(:metadata, 4,
    repeated: true,
    type: Amarula.Protocol.Proto.SyncActionValue.CustomPaymentMethodMetadata
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.CustomPaymentMethodMetadata do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.CustomPaymentMethodsAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:customPaymentMethods, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.SyncActionValue.CustomPaymentMethod
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.DeleteChatAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:messageRange, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.SyncActionMessageRange
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.DeleteIndividualCallLogAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:peerJid, 1, proto3_optional: true, type: :string)
  field(:isIncoming, 2, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.DeleteMessageForMeAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:deleteMedia, 1, proto3_optional: true, type: :bool)
  field(:messageTimestamp, 2, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.DetectedOutcomesStatusAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isEnabled, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.ExternalWebBetaAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isOptIn, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.FavoritesAction.Favorite do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:id, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.FavoritesAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:favorites, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.SyncActionValue.FavoritesAction.Favorite
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.InteractiveMessageAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1,
    type:
      Amarula.Protocol.Proto.SyncActionValue.InteractiveMessageAction.InteractiveMessageActionMode,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.KeyExpiration do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:expiredKeyEpoch, 1, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.LabelAssociationAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:labeled, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.LabelEditAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, proto3_optional: true, type: :string)
  field(:color, 2, proto3_optional: true, type: :int32)
  field(:predefinedId, 3, proto3_optional: true, type: :int32)
  field(:deleted, 4, proto3_optional: true, type: :bool)
  field(:orderIndex, 5, proto3_optional: true, type: :int32)
  field(:isActive, 6, proto3_optional: true, type: :bool)

  field(:type, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.LabelEditAction.ListType,
    enum: true
  )

  field(:isImmutable, 8, proto3_optional: true, type: :bool)
  field(:muteEndTimeMs, 9, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.LabelReorderingAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:sortedLabelIds, 1, repeated: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.LidContactAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:fullName, 1, proto3_optional: true, type: :string)
  field(:firstName, 2, proto3_optional: true, type: :string)
  field(:username, 3, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.LocaleSetting do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:locale, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.LockChatAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:locked, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MaibaAIFeaturesControlAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:aiFeatureStatus, 1,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.SyncActionValue.MaibaAIFeaturesControlAction.MaibaAIFeatureStatus,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MarkChatAsReadAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:read, 1, proto3_optional: true, type: :bool)

  field(:messageRange, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.SyncActionMessageRange
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MarketingMessageAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, proto3_optional: true, type: :string)
  field(:message, 2, proto3_optional: true, type: :string)

  field(:type, 3,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.SyncActionValue.MarketingMessageAction.MarketingMessagePrototypeType,
    enum: true
  )

  field(:createdAt, 4, proto3_optional: true, type: :int64)
  field(:lastSentAt, 5, proto3_optional: true, type: :int64)
  field(:isDeleted, 6, proto3_optional: true, type: :bool)
  field(:mediaId, 7, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MarketingMessageBroadcastAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:repliedCount, 1, proto3_optional: true, type: :int32)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MerchantPaymentPartnerAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:status, 1,
    type: Amarula.Protocol.Proto.SyncActionValue.MerchantPaymentPartnerAction.Status,
    enum: true
  )

  field(:country, 2, type: :string)
  field(:gatewayName, 3, proto3_optional: true, type: :string)
  field(:credentialId, 4, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MusicUserIdAction.MusicUserIdMapEntry do
  @moduledoc false

  use Protobuf, map: true, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: :string)
  field(:value, 2, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MusicUserIdAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:musicUserId, 1, proto3_optional: true, type: :string)

  field(:music_user_id_map, 2,
    repeated: true,
    type: Amarula.Protocol.Proto.SyncActionValue.MusicUserIdAction.MusicUserIdMapEntry,
    json_name: "musicUserIdMap",
    map: true
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.MuteAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:muted, 1, proto3_optional: true, type: :bool)
  field(:muteEndTimestamp, 2, proto3_optional: true, type: :int64)
  field(:autoMuted, 3, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.NewsletterSavedInterestsAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:newsletterSavedInterests, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.NoteEditAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:type, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.NoteEditAction.NoteType,
    enum: true
  )

  field(:chatJid, 2, proto3_optional: true, type: :string)
  field(:createdAt, 3, proto3_optional: true, type: :int64)
  field(:deleted, 4, proto3_optional: true, type: :bool)
  field(:unstructuredContent, 5, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.NotificationActivitySettingAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:notificationActivitySetting, 1,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.SyncActionValue.NotificationActivitySettingAction.NotificationActivitySetting,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.NuxAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:acknowledged, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PaymentInfoAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:cpi, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PaymentTosAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:paymentNotice, 1,
    type: Amarula.Protocol.Proto.SyncActionValue.PaymentTosAction.PaymentNotice,
    enum: true
  )

  field(:accepted, 2, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PinAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:pinned, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PnForLidChatAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:pnJid, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PrimaryFeature do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:flags, 1, repeated: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PrimaryVersionAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:version, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PrivacySettingChannelsPersonalisedRecommendationAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isUserOptedOut, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PrivacySettingDisableLinkPreviewsAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isPreviewsDisabled, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PrivacySettingRelayAllCalls do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isEnabled, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PrivateProcessingSettingAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:privateProcessingStatus, 1,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.SyncActionValue.PrivateProcessingSettingAction.PrivateProcessingStatus,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.PushNameSetting do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:name, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.QuickReplyAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:shortcut, 1, proto3_optional: true, type: :string)
  field(:message, 2, proto3_optional: true, type: :string)
  field(:keywords, 3, repeated: true, type: :string)
  field(:count, 4, proto3_optional: true, type: :int32)
  field(:deleted, 5, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.RecentEmojiWeightsAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:weights, 1, repeated: true, type: Amarula.Protocol.Proto.RecentEmojiWeight)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.RemoveRecentStickerAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:lastStickerSentTs, 1, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.StarAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:starred, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.StatusPostOptInNotificationPreferencesAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:enabled, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.StatusPrivacyAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:mode, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.StatusPrivacyAction.StatusDistributionMode,
    enum: true
  )

  field(:userJid, 2, repeated: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.StickerAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:url, 1, proto3_optional: true, type: :string)
  field(:fileEncSha256, 2, proto3_optional: true, type: :bytes)
  field(:mediaKey, 3, proto3_optional: true, type: :bytes)
  field(:mimetype, 4, proto3_optional: true, type: :string)
  field(:height, 5, proto3_optional: true, type: :uint32)
  field(:width, 6, proto3_optional: true, type: :uint32)
  field(:directPath, 7, proto3_optional: true, type: :string)
  field(:fileLength, 8, proto3_optional: true, type: :uint64)
  field(:isFavorite, 9, proto3_optional: true, type: :bool)
  field(:deviceIdHint, 10, proto3_optional: true, type: :uint32)
  field(:isLottie, 11, proto3_optional: true, type: :bool)
  field(:imageHash, 12, proto3_optional: true, type: :string)
  field(:isAvatarSticker, 13, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.SubscriptionAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isDeactivated, 1, proto3_optional: true, type: :bool)
  field(:isAutoRenewing, 2, proto3_optional: true, type: :bool)
  field(:expirationDate, 3, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.SyncActionMessage do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:timestamp, 2, proto3_optional: true, type: :int64)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.SyncActionMessageRange do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:lastMessageTimestamp, 1, proto3_optional: true, type: :int64)
  field(:lastSystemMessageTimestamp, 2, proto3_optional: true, type: :int64)

  field(:messages, 3,
    repeated: true,
    type: Amarula.Protocol.Proto.SyncActionValue.SyncActionMessage
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.TimeFormatAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:isTwentyFourHourFormatEnabled, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.UGCBot do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:definition, 1, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.UnarchiveChatsSetting do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:unarchiveChats, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.UserStatusMuteAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:muted, 1, proto3_optional: true, type: :bool)
end

defmodule Amarula.Protocol.Proto.SyncActionValue.UsernameChatStartModeAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:chatStartMode, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.UsernameChatStartModeAction.ChatStartMode,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.WaffleAccountLinkStateAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:linkState, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.WaffleAccountLinkStateAction.AccountLinkState,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.SyncActionValue.WamoUserIdentifierAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:identifier, 1, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.SyncActionValue do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:timestamp, 1, proto3_optional: true, type: :int64)

  field(:starAction, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.StarAction
  )

  field(:contactAction, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.ContactAction
  )

  field(:muteAction, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.MuteAction
  )

  field(:pinAction, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.PinAction
  )

  field(:pushNameSetting, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.PushNameSetting
  )

  field(:quickReplyAction, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.QuickReplyAction
  )

  field(:recentEmojiWeightsAction, 11,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.RecentEmojiWeightsAction
  )

  field(:labelEditAction, 14,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.LabelEditAction
  )

  field(:labelAssociationAction, 15,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.LabelAssociationAction
  )

  field(:localeSetting, 16,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.LocaleSetting
  )

  field(:archiveChatAction, 17,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.ArchiveChatAction
  )

  field(:deleteMessageForMeAction, 18,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.DeleteMessageForMeAction
  )

  field(:keyExpiration, 19,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.KeyExpiration
  )

  field(:markChatAsReadAction, 20,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.MarkChatAsReadAction
  )

  field(:clearChatAction, 21,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.ClearChatAction
  )

  field(:deleteChatAction, 22,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.DeleteChatAction
  )

  field(:unarchiveChatsSetting, 23,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.UnarchiveChatsSetting
  )

  field(:primaryFeature, 24,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.PrimaryFeature
  )

  field(:androidUnsupportedActions, 26,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.AndroidUnsupportedActions
  )

  field(:agentAction, 27,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.AgentAction
  )

  field(:subscriptionAction, 28,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.SubscriptionAction
  )

  field(:userStatusMuteAction, 29,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.UserStatusMuteAction
  )

  field(:timeFormatAction, 30,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.TimeFormatAction
  )

  field(:nuxAction, 31,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.NuxAction
  )

  field(:primaryVersionAction, 32,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.PrimaryVersionAction
  )

  field(:stickerAction, 33,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.StickerAction
  )

  field(:removeRecentStickerAction, 34,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.RemoveRecentStickerAction
  )

  field(:chatAssignment, 35,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.ChatAssignmentAction
  )

  field(:chatAssignmentOpenedStatus, 36,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.ChatAssignmentOpenedStatusAction
  )

  field(:pnForLidChatAction, 37,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.PnForLidChatAction
  )

  field(:marketingMessageAction, 38,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.MarketingMessageAction
  )

  field(:marketingMessageBroadcastAction, 39,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.MarketingMessageBroadcastAction
  )

  field(:externalWebBetaAction, 40,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.ExternalWebBetaAction
  )

  field(:privacySettingRelayAllCalls, 41,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.PrivacySettingRelayAllCalls
  )

  field(:callLogAction, 42,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.CallLogAction
  )

  field(:ugcBot, 43, proto3_optional: true, type: Amarula.Protocol.Proto.SyncActionValue.UGCBot)

  field(:statusPrivacy, 44,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.StatusPrivacyAction
  )

  field(:botWelcomeRequestAction, 45,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.BotWelcomeRequestAction
  )

  field(:deleteIndividualCallLog, 46,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.DeleteIndividualCallLogAction
  )

  field(:labelReorderingAction, 47,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.LabelReorderingAction
  )

  field(:paymentInfoAction, 48,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.PaymentInfoAction
  )

  field(:customPaymentMethodsAction, 49,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.CustomPaymentMethodsAction
  )

  field(:lockChatAction, 50,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.LockChatAction
  )

  field(:chatLockSettings, 51,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ChatLockSettings
  )

  field(:wamoUserIdentifierAction, 52,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.WamoUserIdentifierAction
  )

  field(:privacySettingDisableLinkPreviewsAction, 53,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.PrivacySettingDisableLinkPreviewsAction
  )

  field(:deviceCapabilities, 54,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.DeviceCapabilities
  )

  field(:noteEditAction, 55,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.NoteEditAction
  )

  field(:favoritesAction, 56,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.FavoritesAction
  )

  field(:merchantPaymentPartnerAction, 57,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.MerchantPaymentPartnerAction
  )

  field(:waffleAccountLinkStateAction, 58,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.WaffleAccountLinkStateAction
  )

  field(:usernameChatStartMode, 59,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.UsernameChatStartModeAction
  )

  field(:notificationActivitySettingAction, 60,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.NotificationActivitySettingAction
  )

  field(:lidContactAction, 61,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.LidContactAction
  )

  field(:ctwaPerCustomerDataSharingAction, 62,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.CtwaPerCustomerDataSharingAction
  )

  field(:paymentTosAction, 63,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.PaymentTosAction
  )

  field(:privacySettingChannelsPersonalisedRecommendationAction, 64,
    proto3_optional: true,
    type:
      Amarula.Protocol.Proto.SyncActionValue.PrivacySettingChannelsPersonalisedRecommendationAction
  )

  field(:businessBroadcastAssociationAction, 65,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.BusinessBroadcastAssociationAction
  )

  field(:detectedOutcomesStatusAction, 66,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.DetectedOutcomesStatusAction
  )

  field(:maibaAiFeaturesControlAction, 68,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.MaibaAIFeaturesControlAction
  )

  field(:businessBroadcastListAction, 69,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.BusinessBroadcastListAction
  )

  field(:musicUserIdAction, 70,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.MusicUserIdAction
  )

  field(:statusPostOptInNotificationPreferencesAction, 71,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.StatusPostOptInNotificationPreferencesAction
  )

  field(:avatarUpdatedAction, 72,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.AvatarUpdatedAction
  )

  field(:privateProcessingSettingAction, 74,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.PrivateProcessingSettingAction
  )

  field(:newsletterSavedInterestsAction, 75,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.NewsletterSavedInterestsAction
  )

  field(:aiThreadRenameAction, 76,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.AiThreadRenameAction
  )

  field(:interactiveMessageAction, 77,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncActionValue.InteractiveMessageAction
  )
end

defmodule Amarula.Protocol.Proto.SyncdIndex do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:blob, 1, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SyncdMutation do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:operation, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.SyncdMutation.SyncdOperation,
    enum: true
  )

  field(:record, 2, proto3_optional: true, type: Amarula.Protocol.Proto.SyncdRecord)
end

defmodule Amarula.Protocol.Proto.SyncdMutations do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:mutations, 1, repeated: true, type: Amarula.Protocol.Proto.SyncdMutation)
end

defmodule Amarula.Protocol.Proto.SyncdPatch do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:version, 1, proto3_optional: true, type: Amarula.Protocol.Proto.SyncdVersion)
  field(:mutations, 2, repeated: true, type: Amarula.Protocol.Proto.SyncdMutation)

  field(:externalMutations, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ExternalBlobReference
  )

  field(:snapshotMac, 4, proto3_optional: true, type: :bytes)
  field(:patchMac, 5, proto3_optional: true, type: :bytes)
  field(:keyId, 6, proto3_optional: true, type: Amarula.Protocol.Proto.KeyId)
  field(:exitCode, 7, proto3_optional: true, type: Amarula.Protocol.Proto.ExitCode)
  field(:deviceIndex, 8, proto3_optional: true, type: :uint32)
  field(:clientDebugData, 9, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SyncdRecord do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:index, 1, proto3_optional: true, type: Amarula.Protocol.Proto.SyncdIndex)
  field(:value, 2, proto3_optional: true, type: Amarula.Protocol.Proto.SyncdValue)
  field(:keyId, 3, proto3_optional: true, type: Amarula.Protocol.Proto.KeyId)
end

defmodule Amarula.Protocol.Proto.SyncdSnapshot do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:version, 1, proto3_optional: true, type: Amarula.Protocol.Proto.SyncdVersion)
  field(:records, 2, repeated: true, type: Amarula.Protocol.Proto.SyncdRecord)
  field(:mac, 3, proto3_optional: true, type: :bytes)
  field(:keyId, 4, proto3_optional: true, type: Amarula.Protocol.Proto.KeyId)
end

defmodule Amarula.Protocol.Proto.SyncdValue do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:blob, 1, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.SyncdVersion do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:version, 1, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.TapLinkAction do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:title, 1, proto3_optional: true, type: :string)
  field(:tapUrl, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.TemplateButton.CallButton do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayText, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HighlyStructuredMessage
  )

  field(:phoneNumber, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HighlyStructuredMessage
  )
end

defmodule Amarula.Protocol.Proto.TemplateButton.QuickReplyButton do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayText, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HighlyStructuredMessage
  )

  field(:id, 2, proto3_optional: true, type: :string)
end

defmodule Amarula.Protocol.Proto.TemplateButton.URLButton do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:displayText, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HighlyStructuredMessage
  )

  field(:url, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.HighlyStructuredMessage
  )
end

defmodule Amarula.Protocol.Proto.TemplateButton do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:button, 0)

  field(:index, 4, proto3_optional: true, type: :uint32)

  field(:quickReplyButton, 1,
    type: Amarula.Protocol.Proto.TemplateButton.QuickReplyButton,
    oneof: 0
  )

  field(:urlButton, 2, type: Amarula.Protocol.Proto.TemplateButton.URLButton, oneof: 0)
  field(:callButton, 3, type: Amarula.Protocol.Proto.TemplateButton.CallButton, oneof: 0)
end

defmodule Amarula.Protocol.Proto.ThreadID do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:threadType, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ThreadID.ThreadType,
    enum: true
  )

  field(:threadKey, 2, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
end

defmodule Amarula.Protocol.Proto.UrlTrackingMap.UrlTrackingMapElement do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:originalUrl, 1, proto3_optional: true, type: :string)
  field(:unconsentedUsersUrl, 2, proto3_optional: true, type: :string)
  field(:consentedUsersUrl, 3, proto3_optional: true, type: :string)
  field(:cardIndex, 4, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.UrlTrackingMap do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:urlTrackingMapElements, 1,
    repeated: true,
    type: Amarula.Protocol.Proto.UrlTrackingMap.UrlTrackingMapElement
  )
end

defmodule Amarula.Protocol.Proto.UserPassword.TransformerArg.Value do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  oneof(:value, 0)

  field(:asBlob, 1, type: :bytes, oneof: 0)
  field(:asUnsignedInteger, 2, type: :uint32, oneof: 0)
end

defmodule Amarula.Protocol.Proto.UserPassword.TransformerArg do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, proto3_optional: true, type: :string)

  field(:value, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.UserPassword.TransformerArg.Value
  )
end

defmodule Amarula.Protocol.Proto.UserPassword do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:encoding, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.UserPassword.Encoding,
    enum: true
  )

  field(:transformer, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.UserPassword.Transformer,
    enum: true
  )

  field(:transformerArg, 3,
    repeated: true,
    type: Amarula.Protocol.Proto.UserPassword.TransformerArg
  )

  field(:transformedData, 4, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.UserReceipt do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:userJid, 1, type: :string)
  field(:receiptTimestamp, 2, proto3_optional: true, type: :int64)
  field(:readTimestamp, 3, proto3_optional: true, type: :int64)
  field(:playedTimestamp, 4, proto3_optional: true, type: :int64)
  field(:pendingDeviceJid, 5, repeated: true, type: :string)
  field(:deliveredDeviceJid, 6, repeated: true, type: :string)
end

defmodule Amarula.Protocol.Proto.VerifiedNameCertificate.Details do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:serial, 1, proto3_optional: true, type: :uint64)
  field(:issuer, 2, proto3_optional: true, type: :string)
  field(:verifiedName, 4, proto3_optional: true, type: :string)
  field(:localizedNames, 8, repeated: true, type: Amarula.Protocol.Proto.LocalizedName)
  field(:issueTime, 10, proto3_optional: true, type: :uint64)
end

defmodule Amarula.Protocol.Proto.VerifiedNameCertificate do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:details, 1, proto3_optional: true, type: :bytes)
  field(:signature, 2, proto3_optional: true, type: :bytes)
  field(:serverSignature, 3, proto3_optional: true, type: :bytes)
end

defmodule Amarula.Protocol.Proto.WallpaperSettings do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:filename, 1, proto3_optional: true, type: :string)
  field(:opacity, 2, proto3_optional: true, type: :uint32)
end

defmodule Amarula.Protocol.Proto.WebFeatures do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:labelsDisplay, 1,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:voipIndividualOutgoing, 2,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:groupsV3, 3,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:groupsV3Create, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:changeNumberV2, 5,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:queryStatusV3Thumbnail, 6,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:liveLocations, 7,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:queryVname, 8,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:voipIndividualIncoming, 9,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:quickRepliesQuery, 10,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:payments, 11,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:stickerPackQuery, 12,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:liveLocationsFinal, 13,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:labelsEdit, 14,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:mediaUpload, 15,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:mediaUploadRichQuickReplies, 18,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:vnameV2, 19,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:videoPlaybackUrl, 20,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:statusRanking, 21,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:voipIndividualVideo, 22,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:thirdPartyStickers, 23,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:frequentlyForwardedSetting, 24,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:groupsV4JoinPermission, 25,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:recentStickers, 26,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:catalog, 27,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:starredStickers, 28,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:voipGroupCall, 29,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:templateMessage, 30,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:templateMessageInteractivity, 31,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:ephemeralMessages, 32,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:e2ENotificationSync, 33,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:recentStickersV2, 34,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:recentStickersV3, 36,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:userNotice, 37,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:support, 39,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:groupUiiCleanup, 40,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:groupDogfoodingInternalOnly, 41,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:settingsSync, 42,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:archiveV2, 43,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:ephemeralAllowGroupMembers, 44,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:ephemeral24HDuration, 45,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:mdForceUpgrade, 46,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:disappearingMode, 47,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:externalMdOptInAvailable, 48,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )

  field(:noDeleteMessageTimeLimit, 49,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebFeatures.Flag,
    enum: true
  )
end

defmodule Amarula.Protocol.Proto.WebMessageInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:key, 1, type: Amarula.Protocol.Proto.MessageKey)
  field(:message, 2, proto3_optional: true, type: Amarula.Protocol.Proto.Message)
  field(:messageTimestamp, 3, proto3_optional: true, type: :uint64)

  field(:status, 4,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebMessageInfo.Status,
    enum: true
  )

  field(:participant, 5, proto3_optional: true, type: :string)
  field(:messageC2STimestamp, 6, proto3_optional: true, type: :uint64)
  field(:ignore, 16, proto3_optional: true, type: :bool)
  field(:starred, 17, proto3_optional: true, type: :bool)
  field(:broadcast, 18, proto3_optional: true, type: :bool)
  field(:pushName, 19, proto3_optional: true, type: :string)
  field(:mediaCiphertextSha256, 20, proto3_optional: true, type: :bytes)
  field(:multicast, 21, proto3_optional: true, type: :bool)
  field(:urlText, 22, proto3_optional: true, type: :bool)
  field(:urlNumber, 23, proto3_optional: true, type: :bool)

  field(:messageStubType, 24,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebMessageInfo.StubType,
    enum: true
  )

  field(:clearMedia, 25, proto3_optional: true, type: :bool)
  field(:messageStubParameters, 26, repeated: true, type: :string)
  field(:duration, 27, proto3_optional: true, type: :uint32)
  field(:labels, 28, repeated: true, type: :string)
  field(:paymentInfo, 29, proto3_optional: true, type: Amarula.Protocol.Proto.PaymentInfo)

  field(:finalLiveLocation, 30,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.Message.LiveLocationMessage
  )

  field(:quotedPaymentInfo, 31, proto3_optional: true, type: Amarula.Protocol.Proto.PaymentInfo)
  field(:ephemeralStartTimestamp, 32, proto3_optional: true, type: :uint64)
  field(:ephemeralDuration, 33, proto3_optional: true, type: :uint32)
  field(:ephemeralOffToOn, 34, proto3_optional: true, type: :bool)
  field(:ephemeralOutOfSync, 35, proto3_optional: true, type: :bool)

  field(:bizPrivacyStatus, 36,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.WebMessageInfo.BizPrivacyStatus,
    enum: true
  )

  field(:verifiedBizName, 37, proto3_optional: true, type: :string)
  field(:mediaData, 38, proto3_optional: true, type: Amarula.Protocol.Proto.MediaData)
  field(:photoChange, 39, proto3_optional: true, type: Amarula.Protocol.Proto.PhotoChange)
  field(:userReceipt, 40, repeated: true, type: Amarula.Protocol.Proto.UserReceipt)
  field(:reactions, 41, repeated: true, type: Amarula.Protocol.Proto.Reaction)
  field(:quotedStickerData, 42, proto3_optional: true, type: Amarula.Protocol.Proto.MediaData)
  field(:futureproofData, 43, proto3_optional: true, type: :bytes)
  field(:statusPsa, 44, proto3_optional: true, type: Amarula.Protocol.Proto.StatusPSA)
  field(:pollUpdates, 45, repeated: true, type: Amarula.Protocol.Proto.PollUpdate)

  field(:pollAdditionalMetadata, 46,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.PollAdditionalMetadata
  )

  field(:agentId, 47, proto3_optional: true, type: :string)
  field(:statusAlreadyViewed, 48, proto3_optional: true, type: :bool)
  field(:messageSecret, 49, proto3_optional: true, type: :bytes)
  field(:keepInChat, 50, proto3_optional: true, type: Amarula.Protocol.Proto.KeepInChat)
  field(:originalSelfAuthorUserJidString, 51, proto3_optional: true, type: :string)
  field(:revokeMessageTimestamp, 52, proto3_optional: true, type: :uint64)
  field(:pinInChat, 54, proto3_optional: true, type: Amarula.Protocol.Proto.PinInChat)

  field(:premiumMessageInfo, 55,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.PremiumMessageInfo
  )

  field(:is1PBizBotMessage, 56, proto3_optional: true, type: :bool)
  field(:isGroupHistoryMessage, 57, proto3_optional: true, type: :bool)
  field(:botMessageInvokerJid, 58, proto3_optional: true, type: :string)
  field(:commentMetadata, 59, proto3_optional: true, type: Amarula.Protocol.Proto.CommentMetadata)
  field(:eventResponses, 61, repeated: true, type: Amarula.Protocol.Proto.EventResponse)

  field(:reportingTokenInfo, 62,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.ReportingTokenInfo
  )

  field(:newsletterServerId, 63, proto3_optional: true, type: :uint64)

  field(:eventAdditionalMetadata, 64,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.EventAdditionalMetadata
  )

  field(:isMentionedInStatus, 65, proto3_optional: true, type: :bool)
  field(:statusMentions, 66, repeated: true, type: :string)
  field(:targetMessageId, 67, proto3_optional: true, type: Amarula.Protocol.Proto.MessageKey)
  field(:messageAddOns, 68, repeated: true, type: Amarula.Protocol.Proto.MessageAddOn)

  field(:statusMentionMessageInfo, 69,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.StatusMentionMessage
  )

  field(:isSupportAiMessage, 70, proto3_optional: true, type: :bool)
  field(:statusMentionSources, 71, repeated: true, type: :string)
  field(:supportAiCitations, 72, repeated: true, type: Amarula.Protocol.Proto.Citation)
  field(:botTargetId, 73, proto3_optional: true, type: :string)

  field(:groupHistoryIndividualMessageInfo, 74,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.GroupHistoryIndividualMessageInfo
  )

  field(:groupHistoryBundleInfo, 75,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.GroupHistoryBundleInfo
  )

  field(:interactiveMessageAdditionalMetadata, 76,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.InteractiveMessageAdditionalMetadata
  )

  field(:quarantinedMessage, 77,
    proto3_optional: true,
    type: Amarula.Protocol.Proto.QuarantinedMessage
  )
end

defmodule Amarula.Protocol.Proto.WebNotificationsInfo do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.15.0", syntax: :proto3

  field(:timestamp, 2, proto3_optional: true, type: :uint64)
  field(:unreadChats, 3, proto3_optional: true, type: :uint32)
  field(:notifyMessageCount, 4, proto3_optional: true, type: :uint32)
  field(:notifyMessages, 5, repeated: true, type: Amarula.Protocol.Proto.WebMessageInfo)
end
