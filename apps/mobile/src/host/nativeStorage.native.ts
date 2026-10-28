import {
  AESEncryptionKey,
  AESSealedData,
  aesDecryptAsync,
  aesEncryptAsync,
  CryptoDigestAlgorithm,
  digestStringAsync,
  randomUUID,
} from "expo-crypto";
import { Directory, File, Paths } from "expo-file-system";
import * as SecureStore from "expo-secure-store";
import { ensure } from "../runtime/errors";
import { EncryptedFileStorage, serializeHost } from "./encryptedFiles";
import type { HostLifetime } from "./scope";
import { HOST_ENTRY_BYTES } from "./storage";

const options: SecureStore.SecureStoreOptions = {
  keychainAccessible: SecureStore.WHEN_UNLOCKED_THIS_DEVICE_ONLY,
};
export function nativeEncryptedStorage(lifetime: HostLifetime) {
  const hash = (text: string) =>
    digestStringAsync(CryptoDigestAlgorithm.SHA256, text);
  const scopeHash = hash(lifetime.key);
  const directory = new Directory(Paths.document, "tinkerloom-private-host-v1");
  const pointerKey = async (kind: string) =>
    `tl.host.pointer.${await hash(JSON.stringify([lifetime.key, kind]))}`;
  async function key(create: boolean) {
    return serializeHost(`${lifetime.key}:encryption-key`, async () => {
      lifetime.assertActive();
      const name = `tl.host.key.${await scopeHash}`;
      const text = await SecureStore.getItemAsync(name, options);
      lifetime.assertActive();
      if (text !== null) {
        ensure(
          /^[a-f0-9]{64}$/i.test(text),
          "invalid_storage_key",
          "The local encryption key is unreadable.",
        );
        return AESEncryptionKey.import(text, "hex");
      }
      ensure(
        create,
        "missing_storage_key",
        "The encryption key for saved app state is unavailable.",
      );
      const generated = await AESEncryptionKey.generate();
      const encoded = await generated.encoded("hex");
      lifetime.assertActive();
      await SecureStore.setItemAsync(name, encoded, options);
      lifetime.assertActive();
      return generated;
    });
  }
  return new EncryptedFileStorage(lifetime, {
    async readPointer(kind) {
      return SecureStore.getItemAsync(await pointerKey(kind), options);
    },
    async writePointer(kind, name) {
      const pointer = await pointerKey(kind);
      lifetime.assertActive();
      if (name === null) await SecureStore.deleteItemAsync(pointer, options);
      else await SecureStore.setItemAsync(pointer, name, options);
    },
    async readFile(name) {
      const file = new File(directory, name);
      ensure(
        file.exists && file.size <= HOST_ENTRY_BYTES + 128,
        "invalid_storage",
        "The saved encrypted file is missing or too large.",
      );
      return file.bytes();
    },
    async writeFile(name, bytes) {
      lifetime.assertActive();
      directory.create({ idempotent: true, intermediates: true });
      const file = new File(directory, name);
      file.create();
      await file.write(bytes);
    },
    async removeFile(name) {
      const file = new File(directory, name);
      if (file.exists) file.delete();
    },
    async seal(bytes, aad) {
      const secret = await key(true);
      lifetime.assertActive();
      return (
        await aesEncryptAsync(bytes, secret, {
          additionalData: new TextEncoder().encode(aad),
        })
      ).combined();
    },
    async open(bytes, aad) {
      const secret = await key(false);
      lifetime.assertActive();
      return aesDecryptAsync(AESSealedData.fromCombined(bytes), secret, {
        additionalData: new TextEncoder().encode(aad),
      });
    },
    randomName: () => `${randomUUID()}.bin`,
  });
}
