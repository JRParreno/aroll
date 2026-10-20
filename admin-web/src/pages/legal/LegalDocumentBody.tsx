type LegalBlock =
  | { type: "p"; lines: string[] }
  | { type: "h2" | "h3"; text: string }
  | { type: "ul" | "ol"; items: string[] }
  | { type: "hr" };

function parseLegalBody(text: string): LegalBlock[] {
  const blocks: LegalBlock[] = [];
  let paragraph: string[] = [];
  let list: { type: "ul" | "ol"; items: string[] } | null = null;

  const flushParagraph = () => {
    if (!paragraph.length) return;
    blocks.push({ type: "p", lines: paragraph });
    paragraph = [];
  };
  const flushList = () => {
    if (!list) return;
    blocks.push(list);
    list = null;
  };

  for (const raw of text.replace(/\r\n/g, "\n").split("\n")) {
    const stripped = raw.trim();
    if (!stripped) {
      flushParagraph();
      flushList();
      continue;
    }
    if (stripped === "---" || stripped === "***") {
      flushParagraph();
      flushList();
      blocks.push({ type: "hr" });
      continue;
    }
    if (stripped.startsWith("### ")) {
      flushParagraph();
      flushList();
      blocks.push({ type: "h3", text: stripped.slice(4).trim() });
      continue;
    }
    if (stripped.startsWith("## ") || stripped.startsWith("# ")) {
      flushParagraph();
      flushList();
      const textValue = stripped.startsWith("## ")
        ? stripped.slice(3).trim()
        : stripped.slice(2).trim();
      blocks.push({ type: "h2", text: textValue });
      continue;
    }
    let ordered = false;
    let content = stripped;
    if (/^[•\-*]\s/.test(stripped)) {
      content = stripped.slice(2).trim();
    } else {
      const match = stripped.match(/^(\d+)[.)]\s+(.*)$/);
      if (match) {
        ordered = true;
        content = match[2];
      } else {
        flushList();
        paragraph.push(stripped);
        continue;
      }
    }
    flushParagraph();
    const nextType = ordered ? "ol" : "ul";
    if (!list || list.type !== nextType) {
      flushList();
      list = { type: nextType, items: [content] };
    } else {
      list.items.push(content);
    }
  }
  flushParagraph();
  flushList();
  return blocks;
}

export function LegalDocumentBody({ text }: { text: string }) {
  const blocks = parseLegalBody(text);
  if (!blocks.length) {
    return <p className="text-[15px] leading-relaxed text-slate-700">No content.</p>;
  }
  return (
    <div className="space-y-3 text-[15px] leading-relaxed text-slate-700">
      {blocks.map((block, index) => {
        if (block.type === "hr") {
          return <hr key={index} className="border-slate-200" />;
        }
        if (block.type === "h2") {
          return (
            <h3
              key={index}
              className="pt-2 text-[1.02rem] font-semibold tracking-tight text-slate-900"
            >
              {block.text}
            </h3>
          );
        }
        if (block.type === "h3") {
          return (
            <h4 key={index} className="text-[0.95rem] font-semibold text-slate-800">
              {block.text}
            </h4>
          );
        }
        if (block.type === "ul" || block.type === "ol") {
          const Tag = block.type;
          return (
            <Tag key={index} className="list-outside space-y-1.5 pl-5 marker:text-slate-400">
              {block.items.map((item, itemIndex) => (
                <li key={itemIndex}>{item}</li>
              ))}
            </Tag>
          );
        }
        return (
          <p key={index}>
            {block.lines.map((line, lineIndex) => (
              <span key={lineIndex}>
                {lineIndex > 0 ? <br /> : null}
                {line}
              </span>
            ))}
          </p>
        );
      })}
    </div>
  );
}
