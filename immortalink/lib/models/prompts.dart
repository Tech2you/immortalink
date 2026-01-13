class MemoryPrompt {
  final String id; // stable key
  final String lifeStage; // 'early' | 'mid' | 'late'
  final String text;

  const MemoryPrompt({
    required this.id,
    required this.lifeStage,
    required this.text,
  });
}

// 3–7 prompts per stage (we can expand later)
const List<MemoryPrompt> memoryPrompts = [
  // EARLY LIFE
  MemoryPrompt(
    id: 'early_1',
    lifeStage: 'early',
    text: 'Tell a story from your childhood that shaped you.',
  ),
  MemoryPrompt(
    id: 'early_2',
    lifeStage: 'early',
    text: 'What did your parents/guardians teach you (good or bad)?',
  ),
  MemoryPrompt(
    id: 'early_3',
    lifeStage: 'early',
    text: 'What were you most afraid of growing up, and why?',
  ),
  MemoryPrompt(
    id: 'early_4',
    lifeStage: 'early',
    text: 'Who was your first real friend and what do you remember?',
  ),

  // MID LIFE
  MemoryPrompt(
    id: 'mid_1',
    lifeStage: 'mid',
    text: 'Describe a turning point in your life and what changed after.',
  ),
  MemoryPrompt(
    id: 'mid_2',
    lifeStage: 'mid',
    text: 'What mistake taught you the biggest lesson?',
  ),
  MemoryPrompt(
    id: 'mid_3',
    lifeStage: 'mid',
    text: 'What are you most proud of building or achieving?',
  ),
  MemoryPrompt(
    id: 'mid_4',
    lifeStage: 'mid',
    text: 'What did you learn about love, family, or friendship?',
  ),

  // LATE LIFE
  MemoryPrompt(
    id: 'late_1',
    lifeStage: 'late',
    text: 'What do you wish you understood earlier in life?',
  ),
  MemoryPrompt(
    id: 'late_2',
    lifeStage: 'late',
    text: 'What values should our family never compromise on?',
  ),
  MemoryPrompt(
    id: 'late_3',
    lifeStage: 'late',
    text: 'What advice would you give your grandchildren?',
  ),
  MemoryPrompt(
    id: 'late_4',
    lifeStage: 'late',
    text: 'If you could leave one message for the future, what is it?',
  ),
];
