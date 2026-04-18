from duckduckgo_search import DDGS


def search_web(query: str) -> str:
    snippets = []

    with DDGS() as ddgs:
        results = ddgs.text(query, max_results=5)
        for r in results:
            title = r.get("title", "")
            body = r.get("body", "")
            href = r.get("href", "")
            snippets.append(f"Título: {title}\nResumo: {body}\nFonte: {href}")

    if not snippets:
        return "Não encontrei resultados relevantes."

    return "\n\n".join(snippets)