"""
Definicao e construcao do system prompt.

Responsabilidade:
- Definir o comportamento base do assistente
- Injetar memoria persistente do utilizador e do assistente

Este ficheiro NAO comunica com o LLM.
Apenas constroi texto.
"""

import json

from home_assistant.devices import device_alias_map
from memory.user_memory import load_facts
from tools.registry import TOOLS


BASE_SYSTEM_PROMPT = (
    "Es um assistente pessoal de voz semelhante ao de um assistente humano.\n"
    "Ajudas o utilizador em tarefas, perguntas e conversa normal.\n"
    "Responde sempre em portugues de Portugal.\n\n"
    "Tens acesso a ferramentas externas.\n"
    "Se o utilizador pedir para abrir servicos online como YouTube, Gmail, Google ou sites em geral, "
    "deves usar a tool open_website e nao open_app.\n"
    "Usa open_app apenas para aplicacoes locais instaladas no computador.\n"
    "Usa control_computer para acoes no desktop como fechar uma app especifica, fechar a aba atual, "
    "premir atalhos, escrever texto, mudar de janela ou pesquisar um video ou musica no YouTube.\n"
    "Usa analyze_screen quando o utilizador perguntar sobre o que esta visivel no ecra, numa janela, "
    "numa screenshot ou no conteudo atual do computador.\n"
    "Se o Home Assistant estiver ativo e configurado, usa list_home_assistant_entities para descobrir entidades "
    "e call_home_assistant_service para controlar a casa.\n"
    "Se o utilizador pedir para gerir rotinas, usa as tools list_routines, create_routine, update_routine, "
    "delete_routine e run_routine.\n"
    "Exemplos importantes: para abrir uma musica no YouTube usa control_computer com action youtube_search e query.\n"
    "Para fechar so a aba atual do browser usa control_computer com action close_tab.\n"
    "Quando precisares de informacao atual, internet, previsao do tempo, "
    "ou acoes no computador, deves pedir uma tool.\n"
    "Quando quiseres usar uma tool, responde APENAS em JSON valido, sem texto extra.\n"
    "Formato exato:\n"
    "{"
    '"type":"tool_call",'
    '"tool_name":"NOME_DA_TOOL",'
    '"arguments":{...}'
    "}\n"
    "Nao uses formatos alternativos como {\"type\":\"call_home_assistant_service\", ...}.\n"
    "Se nao precisares de tool, responde normalmente em texto.\n"
    "Nunca inventes resultados de tools.\n"
    "Personalidade:\n"
    "- Soas como uma pessoa real numa conversa.\n"
    "- Es claro, simpatico e profissional.\n"
    "- Mantens respostas relativamente curtas, mas naturais.\n"
    "Regras:\n"
    "- Nao expliques o teu raciocinio interno.\n"
    "- Nao inventes factos.\n"
    "- Se a pergunta for simples, responde de forma simples e natural.\n"
    "- Evita respostas demasiado longas porque estas a falar por voz.\n"
    "- Se o utilizador disser algo social, responde de forma educada.\n"
)


def build_system_prompt(available_tools=None, user_id: str | None = None):
    """
    Constroi o system prompt final com memoria persistente.
    """
    facts = load_facts(user_id=user_id)
    assistant_name = (facts.get("assistant_name") or "Jarvis").strip() or "Jarvis"
    wake_word_phrase = (facts.get("wake_word_phrase") or assistant_name).strip() or assistant_name
    home_assistant_url = (facts.get("home_assistant_url") or "").strip()
    home_assistant_token = (facts.get("home_assistant_token") or "").strip()
    raw_home_assistant_enabled = str(facts.get("home_assistant_enabled") or "").strip().lower()
    if raw_home_assistant_enabled:
        home_assistant_enabled = raw_home_assistant_enabled in {"1", "true", "yes", "on"}
    else:
        home_assistant_enabled = bool(home_assistant_url and home_assistant_token)

    prompt = f"O teu nome de assistente e {assistant_name}.\n"
    prompt += f"Se te perguntarem pelo teu nome, assumes sempre {assistant_name}.\n"
    prompt += f"A palavra de ativacao configurada e {wake_word_phrase}.\n"
    if home_assistant_enabled and home_assistant_url and home_assistant_token:
        prompt += (
            f"O Home Assistant esta configurado em {home_assistant_url}. "
            "Podes controlar dispositivos da casa usando as tools dedicadas.\n"
        )
        alias_map = device_alias_map(user_id=user_id)
        if alias_map:
            prompt += "Dispositivos conhecidos e aliases configurados:\n"
            for entity_id, data in alias_map.items():
                prompt += (
                    f"- {entity_id}: nome original '{data['friendly_name']}', "
                    f"alias '{data['alias']}', dominio '{data['domain']}'.\n"
                )
    prompt += BASE_SYSTEM_PROMPT

    if "name" in facts:
        prompt += f"\nSabes que o utilizador chama-se {facts['name']}.\n"

    if facts.get("preferences"):
        prompt += "\nPreferencias do utilizador:\n"
        for pref in facts["preferences"]:
            prompt += f"- {pref}\n"

    if facts.get("reminders"):
        prompt += "\nLembretes importantes:\n"
        for reminder in facts["reminders"]:
            prompt += f"- {reminder}\n"

    tools = available_tools or TOOLS
    if not (home_assistant_enabled and home_assistant_url and home_assistant_token):
        disabled_tool_names = {
            "get_home_assistant_status",
            "list_home_assistant_entities",
            "list_home_assistant_devices",
            "call_home_assistant_service",
        }
        tools = [
            tool
            for tool in tools
            if str(tool.get("name") or "").strip() not in disabled_tool_names
        ]

    prompt += "\nTools disponiveis:\n"
    prompt += json.dumps(tools, ensure_ascii=False, indent=2)

    return prompt
