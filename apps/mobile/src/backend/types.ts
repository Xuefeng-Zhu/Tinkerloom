import type { Definition, Values } from "../preview/model";

export interface User {
  id: string;
  email: string;
  name: string;
}

export interface Workspace {
  id: string;
  name: string;
  /** Omitted only by a historical creation receipt. */
  role?: "owner" | "member";
}

export type AppRole = "owner" | "builder" | "member" | "viewer";
export type GrantRole = Exclude<AppRole, "owner">;
export interface AppCapabilities {
  editDefinition: boolean;
  share: boolean;
  writeRecords: boolean;
  archive: boolean;
  revokeAccess: boolean;
}
export interface AppAccess {
  /** Access fields are absent only on exact historical mutation receipts. */
  role?: AppRole;
  archived?: boolean;
  capabilities?: AppCapabilities;
}
export interface MiniApp extends AppAccess {
  engine?: "bounded.v1" | "appspec.v1";
  id: string;
  workspaceId: string;
  name: string;
}

export interface CreateWorkspace {
  id: string;
  name: string;
}

export interface CreateApp extends CreateWorkspace {
  workspaceId: string;
}

export interface AppDocument extends MiniApp {
  draftRevision: number;
  publishedRevision: number;
  definition: Definition | null;
  publishedDefinition: Definition | null;
  candidateRevision?: number;
  basePublishedRevision?: number;
}

export interface LiveRecord {
  id: string;
  revision: number;
  values: Values;
}

export interface RecordPage {
  records: LiveRecord[];
  definitionRevision: number;
  nextCursor: string | null;
}

export interface SaveDraft {
  appId: string;
  expectedRevision: number;
  expectedPublishedRevision: number;
  operationId: string;
  definition: Definition;
}

export interface PublishApp {
  appId: string;
  expectedRevision: number;
  expectedPublishedRevision: number;
  candidateRevision: number;
  operationId: string;
}

export interface SaveRecord {
  appId: string;
  expectedRevision: number;
  operationId: string;
  id: string;
  definitionRevision: number;
  values: Values;
}

export interface Invitation {
  id: string;
  appId: string;
  issuerId: string;
  role: GrantRole;
  recipientId: string | null;
  createdAt: string;
  expiresAt: string;
  revoked: boolean;
  acceptedBy: string | null;
}
export interface CreateInvitation {
  appId: string;
  id: string;
  operationId: string;
  role: GrantRole;
  recipientId: string | null;
  token: string;
}
export interface AcceptInvitation {
  token: string;
  operationId: string;
}
export interface InvitationPreview {
  appId: string;
  appName: string;
  role: GrantRole;
  expiresAt: string;
  accepted: boolean;
}
export interface RevokeInvitation {
  appId: string;
  invitationId: string;
  operationId: string;
}
export interface AppMember {
  actorId: string;
  role: AppRole | null;
  revision: number;
}
export interface SetGrant {
  appId: string;
  actorId: string;
  role: GrantRole | null;
  expectedRevision: number;
  operationId: string;
}
export interface InvitationPage {
  invitations: Invitation[];
  nextCursor: string | null;
}
export interface MemberPage {
  members: AppMember[];
  nextCursor: string | null;
}
export interface ArchiveApp {
  appId: string;
  operationId: string;
}

export interface AppBackend {
  /** Versioned authenticated Function transport; the host supplies account fencing. */
  executeSpec?(
    payload: Record<string, unknown>,
  ): Promise<Record<string, unknown>>;
  newId(): string;
  currentUser(): Promise<User | null>;
  signIn(email: string, password: string): Promise<User>;
  signUp(email: string, password: string, name: string): Promise<User>;
  signOut(): Promise<void>;
  listWorkspaces(): Promise<Workspace[]>;
  createWorkspace(command: CreateWorkspace): Promise<void>;
  listApps(workspaceId: string): Promise<MiniApp[]>;
  createApp(command: CreateApp): Promise<void>;
  getApp(appId: string): Promise<AppDocument>;
  saveDraft(command: SaveDraft): Promise<AppDocument>;
  publishApp(command: PublishApp): Promise<AppDocument>;
  listRecords(
    appId: string,
    definitionRevision: number,
    afterId?: string,
  ): Promise<RecordPage>;
  saveRecord(command: SaveRecord): Promise<LiveRecord>;
  createInvitation(command: CreateInvitation): Promise<Invitation>;
  acceptInvitation(command: AcceptInvitation): Promise<{ appId: string }>;
  inspectInvitation(token: string): Promise<InvitationPreview>;
  listInvitations(appId: string, afterId?: string): Promise<InvitationPage>;
  revokeInvitation(command: RevokeInvitation): Promise<Invitation>;
  listMembers(appId: string, afterId?: string): Promise<MemberPage>;
  setGrant(command: SetGrant): Promise<AppMember>;
  archiveApp(command: ArchiveApp): Promise<AppDocument>;
}
