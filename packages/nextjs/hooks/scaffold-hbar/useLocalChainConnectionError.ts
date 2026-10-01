import { useQuery } from "@tanstack/react-query";
import { foundry } from "viem/chains";
import { useAccount } from "wagmi";
import { getPublicClient } from "wagmi/actions";
import { wagmiConfig } from "~~/services/web3/wagmiConfig";

/**
 * Returns true when the user is on the local fork chain and the connection fails
 * (e.g. yarn foundry:fork is not running).
 */
export function useLocalChainConnectionError(): boolean {
  const { chain, isConnected } = useAccount();

  const isOnLocalFork = isConnected && chain?.id === foundry.id;

  const { isError } = useQuery({
    queryKey: ["localChainConnection", chain?.id],
    queryFn: async () => {
      const client = getPublicClient(wagmiConfig, { chainId: foundry.id });
      if (!client) throw new Error("No client");
      await client.getBlockNumber();
      return true;
    },
    enabled: isOnLocalFork,
    retry: false,
    staleTime: 5000,
  });

  return isOnLocalFork && isError;
}
