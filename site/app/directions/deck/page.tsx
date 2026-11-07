import type { Metadata } from "next";

import { Deck } from "@/components/landing/directions/deck";
import { DirectionPage } from "@/components/landing/directions/direction-page";

export const metadata: Metadata = { title: "Direction: Deck · SpaceVibe", robots: { index: false } };

export default function DeckDirectionPage() {
  return (
    <DirectionPage current="deck">
      <Deck />
    </DirectionPage>
  );
}
