class Env {
  static const supabaseUrl =
      String.fromEnvironment('https://vbzyvaylfdhwowdbodmk.supabase.co', defaultValue: '');
  static const supabaseAnonKey =
      String.fromEnvironment('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZienl2YXlsZmRod293ZGJvZG1rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjY4MTU5ODAsImV4cCI6MjA4MjM5MTk4MH0.8EVcJ2zzfDJ-TPidHHoJhHpmAECWFveIcOk-89vR6Z4', defaultValue: '');

  static bool get isValid => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
