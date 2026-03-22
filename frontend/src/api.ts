/**
 * API 层
 * 默认同源请求（由前端 Nginx 反代到 backend），开发环境可通过 VITE_API_URL 指定
 */

const API_BASE = import.meta.env.VITE_API_URL || '';

const WORKFLOW_EVENT_START_PLANNING = 'workflow.v2.command.start_planning';

// ── 通用请求 ──

async function fetchJ<T>(url: string): Promise<T> {
  const res = await fetch(url, { cache: 'no-store' });
  if (!res.ok) throw new Error(String(res.status));
  return res.json();
}

async function postJ<T>(url: string, data: unknown): Promise<T> {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  });
  return res.json();
}

async function postEmptyJ<T>(url: string): Promise<T> {
  const res = await fetch(url, { method: 'POST' });
  return res.json();
}

// ── API 接口 ──

export const api = {
  // 核心数据
  liveStatus: () => fetchJ<LiveStatus>(`${API_BASE}/api/tasks/live-status`),
  agentConfig: () => fetchJ<AgentConfig>(`${API_BASE}/api/agent-config`),
  modelChangeLog: () => fetchJ<ChangeLogEntry[]>(`${API_BASE}/api/model-change-log`).catch(() => []),
  officialsStats: () => fetchJ<OfficialsData>(`${API_BASE}/api/officials-stats`),
  morningBrief: () => fetchJ<MorningBrief>(`${API_BASE}/api/morning-brief`),
  morningConfig: () => fetchJ<SubConfig>(`${API_BASE}/api/morning-config`),
  agentsStatus: () => fetchJ<AgentsStatusData>(`${API_BASE}/api/agents-status`),

  // 任务实时动态
  taskActivity: (id: string) =>
    fetchJ<TaskActivityData>(`${API_BASE}/api/task-activity/${encodeURIComponent(id)}`),
  schedulerState: (id: string) =>
    fetchJ<SchedulerStateData>(`${API_BASE}/api/scheduler-state/${encodeURIComponent(id)}`),

  // 技能内容
  skillContent: (agentId: string, skillName: string) =>
    fetchJ<SkillContentResult>(
      `${API_BASE}/api/skill-content/${encodeURIComponent(agentId)}/${encodeURIComponent(skillName)}`
    ),

  // 操作类
  setModel: (agentId: string, model: string) =>
    postJ<ActionResult>(`${API_BASE}/api/set-model`, { agentId, model }),
  agentWake: (agentId: string) =>
    postJ<ActionResult>(`${API_BASE}/api/agent-wake`, { agentId }),
  taskAction: (taskId: string, action: string, reason: string) =>
    postJ<ActionResult>(`${API_BASE}/api/task-action`, { taskId, action, reason }),
  reviewAction: (taskId: string, action: string, comment: string) =>
    postJ<ActionResult>(`${API_BASE}/api/review-action`, { taskId, action, comment }),
  advanceState: (taskId: string, comment: string) =>
    postJ<ActionResult>(`${API_BASE}/api/advance-state`, { taskId, comment }),
  archiveTask: (taskId: string, archived: boolean) =>
    postJ<ActionResult>(`${API_BASE}/api/archive-task`, { taskId, archived }),
  archiveAllDone: () =>
    postJ<ActionResult & { count?: number }>(`${API_BASE}/api/archive-task`, { archiveAllDone: true }),
  schedulerScan: (thresholdSec = 180) =>
    postJ<ActionResult & { count?: number; actions?: ScanAction[]; checkedAt?: string }>(
      `${API_BASE}/api/scheduler-scan`,
      { thresholdSec }
    ),
  schedulerRetry: (taskId: string, reason: string) =>
    postJ<ActionResult>(`${API_BASE}/api/scheduler-retry`, { taskId, reason }),
  schedulerEscalate: (taskId: string, reason: string) =>
    postJ<ActionResult>(`${API_BASE}/api/scheduler-escalate`, { taskId, reason }),
  schedulerRollback: (taskId: string, reason: string) =>
    postJ<ActionResult>(`${API_BASE}/api/scheduler-rollback`, { taskId, reason }),
  dispatchTask: (taskId: string, agent: string, message: string) => {
    const q = new URLSearchParams({ agent, message });
    return postEmptyJ<ActionResult & { agent?: string; message?: string }>(`${API_BASE}/api/tasks/${encodeURIComponent(taskId)}/dispatch?${q.toString()}`)
      .then((r) => {
        // tasks.dispatch 接口历史返回为 {message, agent}，无 ok 字段
        if (typeof r?.ok === 'boolean') return r;
        const { ok: _ignored, ...rest } = (r || {}) as ActionResult & { agent?: string; message?: string };
        return { ok: true, ...rest };
      });
  },
  refreshMorning: () =>
    postJ<ActionResult>(`${API_BASE}/api/morning-brief/refresh`, {}),
  saveMorningConfig: (config: SubConfig) =>
    postJ<ActionResult>(`${API_BASE}/api/morning-config`, config),
  addSkill: (agentId: string, skillName: string, description: string, trigger: string) =>
    postJ<ActionResult>(`${API_BASE}/api/add-skill`, { agentId, skillName, description, trigger }),

  // 远程 Skills 管理
  addRemoteSkill: (agentId: string, skillName: string, sourceUrl: string, description?: string) =>
    postJ<ActionResult & { skillName?: string; agentId?: string; source?: string; localPath?: string; size?: number; addedAt?: string }>(
      `${API_BASE}/api/add-remote-skill`, { agentId, skillName, sourceUrl, description: description || '' }
    ),
  remoteSkillsList: () =>
    fetchJ<RemoteSkillsListResult>(`${API_BASE}/api/remote-skills-list`),
  updateRemoteSkill: (agentId: string, skillName: string) =>
    postJ<ActionResult>(`${API_BASE}/api/update-remote-skill`, { agentId, skillName }),
  removeRemoteSkill: (agentId: string, skillName: string) =>
    postJ<ActionResult>(`${API_BASE}/api/remove-remote-skill`, { agentId, skillName }),

  createTask: (data: CreateTaskPayload) =>
    postJ<ActionResult & { taskId?: string }>(`${API_BASE}/api/create-task`, data),

  // Workflow v2 command bus
  submitWorkflowCommand: (
    workflowId: string,
    eventType: string,
    payload?: Record<string, unknown>,
    producer = 'frontend',
  ) =>
    postJ<ActionResult & { accepted?: boolean; entryId?: string }>(
      `${API_BASE}/api/workflows/${encodeURIComponent(workflowId)}/commands`,
      {
        eventType,
        producer,
        ...(payload ? { payload } : {}),
      }
    ),
  startPlanningWorkflow: (workflowId: string, content = '') =>
    api.submitWorkflowCommand(
      workflowId,
      WORKFLOW_EVENT_START_PLANNING,
      content ? { content } : undefined,
    ),

  artifactDownloadUrl: (path: string) =>
    `${API_BASE}/api/files/download?path=${encodeURIComponent(path)}`,

  // 推送渠道
  notifyChannels: () =>
    fetchJ<NotifyChannelsResult>(`${API_BASE}/api/notify-channels`),
  saveNotifyConfig: (config: { channels: Record<string, Record<string, unknown>> }) =>
    postJ<ActionResult>(`${API_BASE}/api/notify-config`, config),
  testNotifyChannel: (channelId: string, params: Record<string, string>) =>
    postJ<ActionResult & { msg?: string }>(`${API_BASE}/api/notify-test`, { channel_id: channelId, params }),
};

// ── Types ──

export interface ActionResult {
  ok: boolean;
  message?: string;
  error?: string;
}

export interface FlowEntry {
  at?: string;
  ts?: string;
  from: string;
  to: string;
  remark?: string;
  reason?: string;
}

export interface TodoItem {
  id: string | number;
  title: string;
  status: 'not-started' | 'in-progress' | 'completed';
  detail?: string;
}

export interface Heartbeat {
  status: 'active' | 'warn' | 'stalled' | 'unknown' | 'idle';
  label: string;
}

export interface Task {
  id: string;
  title: string;
  state: string;
  org: string;
  now: string;
  eta: string;
  block: string;
  ac: string;
  output: string;
  heartbeat: Heartbeat;
  flow_log: FlowEntry[];
  todos: TodoItem[];
  review_round: number;
  archived: boolean;
  archivedAt?: string;
  updatedAt?: string;
  sourceMeta?: Record<string, unknown>;
  activity?: ActivityEntry[];
  workflowId?: string;
  workflowType?: string;
  projectionVersion?: number;
  currentRevisionId?: string;
  currentAssemblyId?: string;
  pendingReviewCount?: number;
  runningNodeCount?: number;
  _prev_state?: string;
}

export interface SyncStatus {
  ok: boolean;
  [key: string]: unknown;
}

export interface LiveStatus {
  tasks: Task[];
  syncStatus: SyncStatus;
}

export interface AgentInfo {
  id: string;
  label: string;
  emoji: string;
  role: string;
  model: string;
  skills: SkillInfo[];
}

export interface SkillInfo {
  name: string;
  description: string;
  path: string;
}

export interface KnownModel {
  id: string;
  label: string;
  provider: string;
}

export interface AgentConfig {
  agents: AgentInfo[];
  knownModels?: KnownModel[];
}

export interface ChangeLogEntry {
  at: string;
  agentId: string;
  oldModel: string;
  newModel: string;
  rolledBack?: boolean;
}

export interface OfficialInfo {
  id: string;
  label: string;
  emoji: string;
  role: string;
  rank: string;
  model: string;
  model_short: string;
  tokens_in: number;
  tokens_out: number;
  cache_read: number;
  cache_write: number;
  cost_cny: number;
  cost_usd: number;
  sessions: number;
  messages: number;
  tasks_done: number;
  tasks_active: number;
  flow_participations: number;
  merit_score: number;
  merit_rank: number;
  last_active: string;
  heartbeat: Heartbeat;
  participated_edicts: { id: string; title: string; state: string }[];
}

export interface OfficialsData {
  officials: OfficialInfo[];
  totals: { tasks_done: number; cost_cny: number };
  top_official: string;
}

export interface AgentStatusInfo {
  id: string;
  label: string;
  emoji: string;
  role: string;
  status: 'running' | 'idle' | 'offline' | 'unconfigured';
  statusLabel: string;
  lastActive?: string;
}

export interface GatewayStatus {
  alive: boolean;
  probe: boolean;
  status: string;
}

export interface AgentsStatusData {
  ok: boolean;
  gateway: GatewayStatus;
  agents: AgentStatusInfo[];
  checkedAt: string;
}

export interface MorningNewsItem {
  title: string;
  summary?: string;
  desc?: string;
  link: string;
  source: string;
  image?: string;
  pub_date?: string;
}

export interface MorningBrief {
  date?: string;
  generated_at?: string;
  categories: Record<string, MorningNewsItem[]>;
}

export interface SubCategoryConfig {
  name: string;
  enabled: boolean;
}

export interface CustomFeed {
  name: string;
  url: string;
  category: string;
}

export interface SubConfig {
  categories: SubCategoryConfig[];
  keywords: string[];
  custom_feeds: CustomFeed[];
  feishu_webhook: string;
}

export interface ActivityEntry {
  kind: string;
  at?: number | string;
  text?: string;
  thinking?: string;
  agent?: string;
  from?: string;
  to?: string;
  remark?: string;
  tools?: { name: string; input_preview?: string }[];
  tool?: string;
  output?: string;
  exitCode?: number | null;
  items?: TodoItem[];
  diff?: {
    changed?: { id: string; from: string; to: string }[];
    added?: { id: string; title: string }[];
    removed?: { id: string; title: string }[];
  };
}

export interface PhaseDuration {
  phase: string;
  durationSec: number;
  durationText: string;
  ongoing?: boolean;
}

export interface TodosSummary {
  total: number;
  completed: number;
  inProgress: number;
  notStarted: number;
  percent: number;
}

export interface ResourceSummary {
  totalTokens?: number;
  totalCost?: number;
  totalElapsedSec?: number;
}

export interface TaskActivityData {
  ok: boolean;
  message?: string;
  error?: string;
  activity?: ActivityEntry[];
  relatedAgents?: string[];
  agentLabel?: string;
  lastActive?: string;
  phaseDurations?: PhaseDuration[];
  totalDuration?: string;
  todosSummary?: TodosSummary;
  resourceSummary?: ResourceSummary;
  artifacts?: { path: string; kind?: string; exists?: boolean; downloadable?: boolean }[];
  retrySummary?: {
    count: number;
    records: {
      at?: string;
      agent?: string;
      attempts?: number;
      errorType?: string;
      exhausted?: boolean;
    }[];
  };
}

export interface SchedulerInfo {
  retryCount?: number;
  escalationLevel?: number;
  lastDispatchStatus?: string;
  stallThresholdSec?: number;
  enabled?: boolean;
  lastProgressAt?: string;
  lastDispatchAt?: string;
  lastDispatchAgent?: string;
  autoRollback?: boolean;
}

export interface SchedulerStateData {
  ok: boolean;
  error?: string;
  scheduler?: SchedulerInfo;
  stalledSec?: number;
}

export interface SkillContentResult {
  ok: boolean;
  name?: string;
  agent?: string;
  content?: string;
  path?: string;
  error?: string;
}

export interface ScanAction {
  taskId: string;
  action: string;
  to?: string;
  toState?: string;
  stalledSec?: number;
}

export interface CreateTaskPayload {
  title: string;
  org: string;
  targetDept?: string;
  priority?: string;
  templateId?: string;
  params?: Record<string, string>;
}

export interface RemoteSkillItem {
  skillName: string;
  agentId: string;
  sourceUrl: string;
  description: string;
  localPath: string;
  addedAt: string;
  lastUpdated: string;
  status: 'valid' | 'not-found' | string;
}

export interface RemoteSkillsListResult {
  ok: boolean;
  remoteSkills?: RemoteSkillItem[];
  count?: number;
  listedAt?: string;
  error?: string;
}

// ── 推送渠道 ──

export interface ChannelSchemaField {
  key: string;
  label: string;
  type: 'text' | 'password' | 'select' | 'number';
  placeholder?: string;
  required?: boolean;
  default?: string;
  options?: string[];
}

export interface ChannelMeta {
  channel_id: string;
  display_name: string;
  icon: string;
  config_schema: ChannelSchemaField[];
  enabled: boolean;
  params: Record<string, string>;
  secret_state?: Record<string, { has_value: boolean; masked: string }>;
}

export interface NotifyChannelsResult {
  ok: boolean;
  channels?: ChannelMeta[];
  error?: string;
}
