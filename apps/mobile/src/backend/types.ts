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
}
