TOOLS = [
    {
        "name": "get_home_assistant_status",
        "description": "Verifica se a ligacao ao Home Assistant esta configurada e ativa.",
        "parameters": {}
    },
    {
        "name": "list_home_assistant_entities",
        "description": "Lista entidades do Home Assistant para poderes descobrir luzes, interruptores, sensores e outros dispositivos.",
        "parameters": {
            "domain": "string"
        }
    },
    {
        "name": "list_home_assistant_devices",
        "description": "Lista os dispositivos Home Assistant sincronizados com aliases e nomes configurados para o assistente os reconhecer.",
        "parameters": {
            "domain": "string"
        }
    },
    {
        "name": "call_home_assistant_service",
        "description": "Executa um servico do Home Assistant para controlar dispositivos ou automacoes.",
        "parameters": {
            "domain": "string",
            "service": "string",
            "entity_id": "string",
            "service_data": "object"
        }
    },
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
    },
    {
        "name": "list_routines",
        "description": "Lista as rotinas guardadas pelo assistente.",
        "parameters": {}
    },
    {
        "name": "create_routine",
        "description": "Cria uma rotina persistente com nome, descricao, trigger opcional e acoes.",
        "parameters": {
            "name": "string",
            "description": "string",
            "trigger_text": "string",
            "enabled": "boolean",
            "actions": "array"
        }
    },
    {
        "name": "update_routine",
        "description": "Atualiza uma rotina existente pelo identificador.",
        "parameters": {
            "routine_id": "string",
            "name": "string",
            "description": "string",
            "trigger_text": "string",
            "enabled": "boolean",
            "actions": "array"
        }
    },
    {
        "name": "delete_routine",
        "description": "Remove uma rotina existente pelo identificador.",
        "parameters": {
            "routine_id": "string"
        }
    },
    {
        "name": "run_routine",
        "description": "Executa manualmente uma rotina existente pelo identificador.",
        "parameters": {
            "routine_id": "string"
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
