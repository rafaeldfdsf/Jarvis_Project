TOOLS = [
    {
        "name": "get_weather",
        "description": "Obtem a previsao do tempo para uma cidade.",
        "parameters": {
            "city": "string"
        }
    },
    {
        "name": "search_web",
        "description": "Pesquisa informacao atual na web.",
        "parameters": {
            "query": "string"
        }
    },
    {
        "name": "open_website",
        "description": "Abre um site no navegador.",
        "parameters": {
            "url": "string"
        }
    },
    {
        "name": "open_app",
        "description": "Abre uma aplicacao local instalada no computador.",
        "parameters": {
            "app_name": "string"
        }
    },
    {
        "name": "control_computer",
        "description": "Executa acoes genericas no computador, como fechar uma app, fechar a aba atual, escrever texto, premir atalhos, mudar de janela ou pesquisar no YouTube.",
        "parameters": {
            "action": "string",
            "app_name": "string",
            "window_title": "string",
            "url": "string",
            "query": "string",
            "text": "string",
            "keys": "string"
        }
    },
    {
        "name": "analyze_screen",
        "description": "Analisa o que esta visivel no ecra atual e responde a uma pergunta sobre isso.",
        "parameters": {
            "question": "string"
        }
    },
    {
        "name": "type_text",
        "description": "Escreve texto no campo ativo.",
        "parameters": {
            "text": "string"
        }
    },
    {
        "name": "press_keys",
        "description": "Prime combinacoes de teclas conhecidas, como ctrl+s.",
        "parameters": {
            "keys": "string"
        }
    }
]

LOCAL_AUTOMATION_TOOL_NAMES = {
    "type_text",
    "press_keys",
}

CLIENT_ACTION_TOOL_NAMES = {
    "open_website",
    "open_app",
    "control_computer",
}


def available_tools(enable_local_automation: bool = True) -> list[dict]:
    if enable_local_automation:
        return list(TOOLS)

    return [
        tool
        for tool in TOOLS
        if tool["name"] not in LOCAL_AUTOMATION_TOOL_NAMES
    ]


API_SAFE_TOOLS = available_tools(enable_local_automation=False)
