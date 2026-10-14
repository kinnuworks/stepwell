import EmbedCard from "@/components/EmbedCard";

export const metadata = { title: "Stepwell cover card" };

/** A small card any app can drop into an iframe next to a vault: <iframe src="/embed?ref=your-app">. */
export default async function Embed({ searchParams }: { searchParams: Promise<{ ref?: string }> }) {
  const { ref } = await searchParams;
  return <main style={{ padding: 12 }}><EmbedCard appRef={ref ?? "embed"} /></main>;
}
