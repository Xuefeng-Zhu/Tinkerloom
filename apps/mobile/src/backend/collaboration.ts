import { isCivilDate } from "../preview/model";
import { canonicalText } from "../preview/canonicalText";
import type {
  AcceptInvitation,
  AppMember,
  CreateInvitation,
  GrantRole,
  Invitation,
  InvitationPage,
  InvitationPreview,
  MemberPage,
  RevokeInvitation,
  SetGrant,
} from "./types";
import {
  exactKeys,
  id,
  validId,
  invalidRequest,
  invalidResponse,
  object,
  operation,
  pageCursor,
  pageInput,
  revision,
  validRevision,
} from "./validation";

export type RpcRequest = (
  payload: Record<string, unknown>,
  mutation?: boolean,
) => Promise<Record<string, unknown>>;
const tokenPattern = /^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$/;
const validToken = (value: unknown): value is string =>
  typeof value === "string" && tokenPattern.test(value);
const roles = ["builder", "member", "viewer"];
function grantRole(value: unknown): value is GrantRole {
  return roles.includes(value as string);
}
function instant(value: unknown, mutation: boolean): number {
  if (typeof value !== "string") invalidResponse(mutation);
  const match =
    /^(\d{4}-\d{2}-\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{3}|\d{6})Z$/.exec(value);
  if (
    !match ||
    !isCivilDate(match[1]) ||
    Number(match[2]) > 23 ||
    Number(match[3]) > 59 ||
    Number(match[4]) > 59
  )
    invalidResponse(mutation);
  const time = Date.parse(value);
  if (!Number.isFinite(time)) invalidResponse(mutation);
  return time;
}
function invitation(
  value: unknown,
  appId: string,
  mutation = false,
): Invitation {
  const data = object(value, mutation);
  exactKeys(
    data,
    [
      "id",
      "appId",
      "issuerId",
      "role",
      "recipientId",
      "createdAt",
      "expiresAt",
      "revoked",
      "acceptedBy",
    ],
    mutation,
  );
  if (
    !grantRole(data.role) ||
    typeof data.revoked !== "boolean" ||
    id(data.appId, mutation) !== appId
  )
    invalidResponse(mutation);
  const created = instant(data.createdAt, mutation);
  const expires = instant(data.expiresAt, mutation);
  if (
    expires - created !== 7 * 24 * 60 * 60 * 1000 ||
    (data.recipientId !== null &&
      data.acceptedBy !== null &&
      data.recipientId !== data.acceptedBy)
  )
    invalidResponse(mutation);
  return {
    id: id(data.id, mutation),
    appId,
    issuerId: id(data.issuerId, mutation),
    role: data.role,
    recipientId:
      data.recipientId === null ? null : id(data.recipientId, mutation),
    createdAt: data.createdAt as string,
    expiresAt: data.expiresAt as string,
    revoked: data.revoked,
    acceptedBy: data.acceptedBy === null ? null : id(data.acceptedBy, mutation),
  };
}
function member(
  value: unknown,
  mutation = false,
  allowRevoked = false,
): AppMember {
  const data = object(value, mutation);
  exactKeys(data, ["actorId", "role", "revision"], mutation);
  if (!(
    data.role === "owner" ||
    grantRole(data.role) ||
    (allowRevoked && data.role === null)
  ))
    invalidResponse(mutation);
  const counter = revision(
    data.revision,
    data.role === "owner" ? 0 : 1,
    mutation,
  );
  if (data.role === "owner" && counter !== 0) invalidResponse(mutation);
  return {
    actorId: id(data.actorId, mutation),
    role: data.role as AppMember["role"],
    revision: counter,
  };
}

/** Collaboration uses the same authenticated Function transport as app data. */
export class CollaborationRpc {
  constructor(private request: RpcRequest) {}
  async inspectInvitation(token: string): Promise<InvitationPreview> {
    if (!validToken(token)) invalidRequest();
    const envelope = await this.request({ op: "inspectInvitation", token });
    exactKeys(envelope, ["invitation"]);
    const data = object(envelope.invitation);
    exactKeys(data, ["appId", "appName", "role", "expiresAt", "accepted"]);
    if (
      typeof data.appName !== "string" ||
      !data.appName ||
      data.appName.length > 128 ||
      canonicalText(data.appName) !== data.appName ||
      !grantRole(data.role) ||
      typeof data.accepted !== "boolean"
    )
      invalidResponse();
    instant(data.expiresAt, false);
    return {
      appId: id(data.appId),
      appName: data.appName,
      role: data.role,
      expiresAt: data.expiresAt as string,
      accepted: data.accepted,
    };
  }
  async createInvitation(command: CreateInvitation): Promise<Invitation> {
    operation(command);
    if (
      !validId(command.id) ||
      !grantRole(command.role) ||
      (command.recipientId !== null && !validId(command.recipientId)) ||
      !validToken(command.token)
    )
      invalidRequest();
    const data = await this.request(
      { op: "createInvitation", ...command },
      true,
    );
    exactKeys(data, ["invitation"], true);
    const result = invitation(data.invitation, command.appId, true);
    if (
      result.id !== command.id ||
      result.role !== command.role ||
      result.recipientId !== command.recipientId ||
      result.revoked ||
      result.acceptedBy !== null
    )
      invalidResponse(true);
    return result;
  }
  async acceptInvitation(
    command: AcceptInvitation,
  ): Promise<{ appId: string }> {
    if (!validId(command.operationId) || !validToken(command.token))
      invalidRequest();
    const data = await this.request(
      { op: "acceptInvitation", ...command },
      true,
    );
    exactKeys(data, ["appId"], true);
    return { appId: id(data.appId, true) };
  }
  async listInvitations(
    appId: string,
    afterId?: string,
  ): Promise<InvitationPage> {
    const data = await this.request({
      op: "listInvitations",
      ...pageInput(appId, afterId),
    });
    exactKeys(data, ["invitations", "nextCursor"]);
    if (!Array.isArray(data.invitations) || data.invitations.length > 25)
      invalidResponse();
    const invitations = data.invitations.map((value) =>
      invitation(value, appId),
    );
    if (
      new Set(invitations.map((row) => row.id)).size !== invitations.length ||
      invitations.some((row) => row.id === afterId)
    )
      invalidResponse();
    return { invitations, nextCursor: pageCursor(data.nextCursor, afterId) };
  }
  async revokeInvitation(command: RevokeInvitation): Promise<Invitation> {
    operation(command);
    if (!validId(command.invitationId)) invalidRequest();
    const data = await this.request(
      { op: "revokeInvitation", ...command },
      true,
    );
    exactKeys(data, ["invitation"], true);
    const result = invitation(data.invitation, command.appId, true);
    if (result.id !== command.invitationId || !result.revoked)
      invalidResponse(true);
    return result;
  }
  async listMembers(appId: string, afterId?: string): Promise<MemberPage> {
    const data = await this.request({
      op: "listMembers",
      ...pageInput(appId, afterId),
    });
    exactKeys(data, ["members", "nextCursor"]);
    if (
      !Array.isArray(data.members) ||
      data.members.length > (afterId === undefined ? 51 : 50)
    )
      invalidResponse();
    const members = data.members.map((value) => member(value));
    if (
      new Set(members.map((row) => row.actorId)).size !== members.length ||
      (afterId === undefined
        ? members[0]?.role !== "owner" ||
          members.slice(1).some((row) => row.role === "owner")
        : members.some((row) => row.role === "owner"))
    )
      invalidResponse();
    return { members, nextCursor: pageCursor(data.nextCursor, afterId) };
  }
  async setGrant(command: SetGrant): Promise<AppMember> {
    operation(command);
    if (
      !validId(command.actorId) ||
      !(command.role === null || grantRole(command.role)) ||
      !validRevision(command.expectedRevision, 1)
    )
      invalidRequest();
    const data = await this.request({ op: "setGrant", ...command }, true);
    exactKeys(data, ["member"], true);
    const result = member(data.member, true, true);
    if (
      result.actorId !== command.actorId ||
      result.role !== command.role ||
      result.revision !== command.expectedRevision + 1
    )
      invalidResponse(true);
    return result;
  }
}
