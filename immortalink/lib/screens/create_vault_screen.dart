import 'package:flutter/material.dart';
import 'package:immortalink_app/auth_gate.dart';
import 'package:immortalink_app/vaults_screen.dart';

class CreateVaultScreen extends StatefulWidget {
  const CreateVaultScreen({Key? key}) : super(key: key);

  @override
  State<CreateVaultScreen> createState() => _CreateVaultScreenState();
}

class _CreateVaultScreenState extends State<CreateVaultScreen> {
  final _formKey = GlobalKey<FormState>();
  String _vaultName = '';

  void _createVault() {
    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();
      // Navigate to VaultsScreen or perform any additional logic
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => VaultsScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Vault'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Vault Name'),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter a vault name';
                  }
                  return null;
                },
                onSaved: (value) {
                  _vaultName = value ?? '';
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _createVault,
                child: const Text('Create'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
