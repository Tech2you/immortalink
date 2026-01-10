import 'package:flutter/material.dart';

class VaultHomeScreen extends StatelessWidget {
  final String vaultId;
  final String vaultName;

  const VaultHomeScreen({
    super.key,
    required this.vaultId,
    required this.vaultName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(vaultName)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Vault Home (next)\n\nVault ID:\n$vaultId',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}
