import type { Definition, Values } from "../preview/model";

export interface User {
  id: string;
  email: string;
  name: string;
}

export interface Workspace {
  id: string;
  name: string;
}

export interface MiniApp {
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
  operationId: string;
  definition: Definition;
}

export interface PublishApp {
  appId: string;
  expectedRevision: number;
  operationId: string;
}

export interface SaveRecord extends PublishApp {
  id: string;
  definitionRevision: number;
  values: Values;
}

export interface AppBackend {
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
}
