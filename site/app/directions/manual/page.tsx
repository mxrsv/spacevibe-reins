import type { Metadata } from "next";

import { DirectionPage } from "@/components/landing/directions/direction-page";
import { Manual } from "@/components/landing/directions/manual";

export const metadata: Metadata = { title: "Direction: Manual · SpaceVibe", robots: { index: false } };

export default function ManualDirectionPage() {
  return (
    <DirectionPage current="manual">
      <Manual />
    </DirectionPage>
  );
}
