# ssh

## Connect to your Mac from iPhone

1. **Enable SSH on Mac:** System Settings → General → Sharing → Remote Login
2. **Find Mac IP:** System Settings → Wi-Fi → click network → copy IP address
3. **Same Wi-Fi** for both devices
4. **Create key in app:** SSH Keys → + → Secure Enclave → Add → tap key → copy public key
5. **Authorize on Mac:**
   ```bash
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   echo "ecdsa-sha2-nistp256 AAAA..." >> ~/.ssh/authorized_keys
   chmod 600 ~/.ssh/authorized_keys
   ```
6. **Connect:** New connection → Mac IP, port 22, your username, Secure Enclave Key
