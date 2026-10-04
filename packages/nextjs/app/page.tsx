import { Landing } from "~~/components/landing/Landing";
import { getMetadata } from "~~/utils/scaffold-hbar/getMetadata";

export const metadata = getMetadata({
  title: "Forklab · Hedera Schedule Service emulator",
  description:
    "A Scaffold-HBAR template that emulates HIP-1215 at 0x16b on a pinned Hedera fork, with real SaucerSwap, Supra, and HTS state.",
});

export default function Home() {
  return <Landing />;
}
