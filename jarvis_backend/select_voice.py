"""Script para testar vozes do sistema."""

import pyttsx3

def test_voices():
    """Lista e testa todas as vozes disponíveis."""
    engine = pyttsx3.init()
    voices = engine.getProperty('voices')
    
    print("\n" + "="*70)
    print("TESTE DE VOZES - JARVIS AGENT")
    print("="*70 + "\n")
    
    if len(voices) == 0:
        print("❌ Nenhuma voz encontrada!")
        return
    
    print(f"Total de vozes: {len(voices)}\n")
    
    for i, voice in enumerate(voices):
        lang = str(voice.languages) if hasattr(voice, 'languages') else "?"
        print(f"[{i}] {voice.name} | {lang}")
    
    print("\n" + "-"*70)
    print("Digite o número da voz para testar (ou 'sair')\n")
    
    while True:
        try:
            choice = input("Voz: ").strip()
            if choice.lower() in {'sair', 'quit', 'exit'}:
                break
            
            idx = int(choice)
            if 0 <= idx < len(voices):
                engine.setProperty('voice', voices[idx].id)
                engine.setProperty('rate', 150)
                
                test_text = "Olá! Sou o Jarvis. Como posso ajudar?"
                print(f"\n🔊 Testando: {voices[idx].name}")
                print(f"Frase: {test_text}\n")
                
                engine.say(test_text)
                engine.runAndWait()
                print()
            else:
                print("❌ Número inválido\n")
        except ValueError:
            print("❌ Digite um número\n")
        except Exception as e:
            print(f"❌ Erro: {e}\n")

if __name__ == "__main__":
    test_voices()
