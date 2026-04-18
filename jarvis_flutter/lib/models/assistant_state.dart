/// Define os estados visuais e funcionais do assistente.
/// Vamos usar isto para mudar a animação e o texto no ecrã.
enum AssistantState {
  idle, // parado, à espera
  listening, // a ouvir o utilizador
  thinking, // já ouviu e está a processar
  speaking, // está a responder por voz
}
