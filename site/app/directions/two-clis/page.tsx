import type { Metadata } from "next";

import { DirectionPage } from "@/components/landing/directions/direction-page";
import { TwoClis } from "@/components/landing/directions/two-clis";

export const metadata: Metadata = { title: "Direction: Two CLIs · SpaceVibe", robots: { index: false } };

export default function TwoClisDirectionPage() {
  return (
    <DirectionPage current="two-clis">
      <TwoClis />
    </DirectionPage>
  );
}
