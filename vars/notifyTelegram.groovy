def call(String message) {
  withCredentials([usernamePassword(credentialsId: 'a25d8b20-4a81-43e9-ac37-dcfb5285790a', usernameVariable: 'TELEGRAM_BOT_CREDS_USR', passwordVariable: 'TELEGRAM_BOT_CREDS_PWD')]) {
    env['TELEGRAM_BOT_MSG'] = message
    sh('curl -s -X POST https://api.telegram.org/$TELEGRAM_BOT_CREDS_PWD/sendMessage -d chat_id=$TELEGRAM_BOT_CREDS_USR -d text="$TELEGRAM_BOT_MSG"')
  }
}
