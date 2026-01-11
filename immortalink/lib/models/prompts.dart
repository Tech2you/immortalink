class MemoryPrompt {
  final String lifeStage; // early | mid | late
  final String key; // early_01
  final String text;

  const MemoryPrompt(this.lifeStage, this.key, this.text);
}

const memoryPrompts = <MemoryPrompt>[
  // EARLY LIFE
  MemoryPrompt('early', 'early_01', 'What is your earliest clear memory?'),
  MemoryPrompt('early', 'early_02', 'Describe your home and family life growing up.'),
  MemoryPrompt('early', 'early_03', 'What did you fear or love most as a child?'),
  MemoryPrompt('early', 'early_04', 'A lesson you learned young that stayed with you.'),
  MemoryPrompt('early', 'early_05', 'A moment you felt proud as a kid/teen.'),

  // MID LIFE
  MemoryPrompt('mid', 'mid_01', 'What period of your life shaped you the most?'),
  MemoryPrompt('mid', 'mid_02', 'What relationships mattered most and why?'),
  MemoryPrompt('mid', 'mid_03', 'Hardest season you went through and how you survived it.'),
  MemoryPrompt('mid', 'mid_04', 'Biggest regret (and what you learned from it).'),
  MemoryPrompt('mid', 'mid_05', 'Your best advice about work/money/purpose.'),

  // LATE LIFE
  MemoryPrompt('late', 'late_01', 'What do you wish your family remembers about you?'),
  MemoryPrompt('late', 'late_02', 'What are you most grateful for?'),
  MemoryPrompt('late', 'late_03', 'What do you want to say to your future grandkids?'),
  MemoryPrompt('late', 'late_04', 'Your rules for a good life (simple and honest).'),
  MemoryPrompt('late', 'late_05', 'Stories you never want to be forgotten.'),
];
