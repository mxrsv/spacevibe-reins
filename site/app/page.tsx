import { ActivityVisual } from "@/components/landing/activity-visual";
import { ACTIVITY, LOADOUT, RULES, TOKENS } from "@/components/landing/content";
import { DownloadBand } from "@/components/landing/download-band";
import { FeatureSection } from "@/components/landing/feature-section";
import { Hero } from "@/components/landing/hero";
import { LoadoutVisual } from "@/components/landing/loadout-visual";
import { PrivateSection } from "@/components/landing/private-section";
import { RulesVisual } from "@/components/landing/rules-visual";
import { LANDING_ROOT_ID, ScrollReveal } from "@/components/landing/scroll-reveal";
import { SiteFooter } from "@/components/landing/site-footer";
import { SiteHeader } from "@/components/landing/site-header";
import { TokensVisual } from "@/components/landing/tokens-visual";

/**
 * spacevibe.dev — one page. Hero with the planet scene, one band per tab
 * (Loadout, Rules, Activity, Tokens), the privacy guarantees, the download band.
 */
export default function LandingPage() {
  return (
    <div id={LANDING_ROOT_ID} className="min-h-dvh bg-bg">
      <SiteHeader />
      <main id="main">
        <Hero />
        <FeatureSection id={LOADOUT.id} heading={LOADOUT.heading} body={LOADOUT.body}>
          <LoadoutVisual />
        </FeatureSection>
        <FeatureSection id={RULES.id} heading={RULES.heading} body={RULES.body} reverse>
          <RulesVisual />
        </FeatureSection>
        <FeatureSection id={ACTIVITY.id} heading={ACTIVITY.heading} body={ACTIVITY.body}>
          <ActivityVisual />
        </FeatureSection>
        <FeatureSection id={TOKENS.id} heading={TOKENS.heading} body={TOKENS.body} reverse>
          <TokensVisual />
        </FeatureSection>
        <PrivateSection />
        <DownloadBand />
      </main>
      <SiteFooter />
      <ScrollReveal />
    </div>
  );
}
