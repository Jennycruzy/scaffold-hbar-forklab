const localRpc = process.env.FORKLAB_LOCAL_RPC_URL ?? "http://127.0.0.1:8545";

export async function localRpcCall<T>(method: string, params: unknown[] = []): Promise<T> {
  const response = await fetch(localRpc, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: Date.now(), method, params }),
    cache: "no-store",
  });
  const body = (await response.json()) as { result?: T; error?: { message?: string } };
  if (!response.ok || body.error) throw new Error(body.error?.message ?? `Local RPC returned ${response.status}`);
  return body.result as T;
}

export const localRpcUrl = localRpc;
