export type StaffRole = "viewer" | "moderator" | "admin";

export type CaseStatus = "open" | "approved" | "rejected" | "hidden";
export type CaseStatusFilter = CaseStatus | "all";
export type CaseSource = "publish" | "report" | "appeal" | "manual";
export type CaseCategory = "sexual" | "gore" | "hate" | "ip_character" | null;
export type Confidence = "high" | "low" | null;

export interface WhoAmI {
  user_id: string;
  role: StaffRole;
}

export interface QueueCase {
  case_id: string;
  entry_id: string;
  art_hash: string;
  source: CaseSource;
  status: CaseStatus;
  category: CaseCategory;
  confidence: Confidence;
  assigned_staff_id: string | null;
  opened_reason_code: string | null;
  created_at: string;
  updated_at: string;
  resolved_at: string | null;
  entry_owner_id: string;
  entry_display_name: string | null;
  entry_report_count: number;
  thumb_url: string | null;
}

export interface QueueListResult {
  cases: QueueCase[];
  page: number;
  per_page: number;
  total: number;
}

export interface ModerationRun {
  pass: 1 | 2;
  decision: "approve" | "reject" | "uncertain";
  category: CaseCategory;
  confidence: Confidence;
  reason_code: string | null;
  evidence: { matched_name?: string; [key: string]: unknown } | null;
  model: string | null;
  policy_version: string | number | null;
  created_at: string;
}

export interface GalleryReport {
  category: string;
  note: string | null;
  resolution_state: "pending" | "upheld" | "dismissed";
  created_at: string;
  reporter_id: string;
}

export interface ModerationDecisionRow {
  staff_id: string;
  action: string;
  reason_code: string;
  note: string | null;
  created_at: string;
}

/** moderation_cases / gallery_entries rows aren't fully spec'd — kept loose and
 * rendered generically alongside the known fields we do rely on. */
export type LooseRow = Record<string, unknown>;

export interface CaseDetailResult {
  case: LooseRow & Partial<QueueCase>;
  entry: LooseRow & { thumb_url?: string | null; sheet_url?: string | null };
  runs: ModerationRun[];
  reports: GalleryReport[];
  decisions: ModerationDecisionRow[];
}

export interface ReportsListResult {
  reports: (GalleryReport & { entry_id: string })[];
  page: number;
  per_page: number;
  total: number;
}

export type DecideAction = "approve" | "reject" | "hide" | "restore" | "escalate" | "assign";

export interface DecideResult {
  ok?: true;
  case_status?: string;
  after?: LooseRow;
  idempotent_replay?: true;
  case_id?: string;
}

export interface ProfileSanction {
  id: string;
  profile_id: string;
  scope: "atlas_publish" | "atlas_report";
  reason_code: string;
  note: string | null;
  expires_at: string | null;
  revoked_at: string | null;
  created_at: string;
}

export interface SeekerProfileResult {
  profile: { id: string; seeker_name: string | null };
  publications: LooseRow[];
  sanctions: ProfileSanction[];
  reports_upheld: number;
  reports_dismissed: number;
}

export interface StaffRow {
  user_id: string;
  role: StaffRole;
  email: string;
  granted_by: string | null;
  created_at: string;
  updated_at: string;
}

export interface AuditEntry {
  id: string;
  actor_id: string;
  action: string;
  target_type: string;
  target_id: string;
  before: LooseRow | null;
  after: LooseRow | null;
  created_at: string;
}

export interface AuditListResult {
  entries: AuditEntry[];
  page: number;
  per_page: number;
  total: number;
}

export interface AnalyticsResult {
  since: string;
  open_cases: number;
  oldest_open_case_age_seconds: number | null;
  decisions_by_action: Record<string, number>;
  pass_outcomes: Record<string, number>;
  manual_outcomes: Record<string, number>;
  appeal_total: number;
  appeal_approved: number;
  report_states: Record<string, number>;
  active_sanctions: number;
  avg_time_to_decision_seconds: number | null;
}
