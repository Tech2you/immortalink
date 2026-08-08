class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vbzyvaylfdhwowdbodmk.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZienl2YXlsZmRod293ZGJvZG1rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY4MTU5ODAsImV4cCI6MjA4MjM5MTk4MH0.8EVcJ2zzfDJ-TPidHHoJhHpmAECWFveIcOk-89vR6Z4',
  );

  static bool get isValid =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
