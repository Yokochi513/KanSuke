/**
 * Google フォームの回答を GitHub Issue として自動登録する。
 *
 * 設置手順は README.md を参照。
 * このスクリプトは Google フォーム側（スプレッドシート側ではない）に
 * バインドすること（e.response.getItemResponses() を使うため）。
 */
function onFormSubmit(e) {
  const props = PropertiesService.getScriptProperties();
  const token = props.getProperty('GITHUB_TOKEN');
  const repo = props.getProperty('GITHUB_REPO'); // 例: "Yokochi513/KanSuke"
  const label = props.getProperty('GITHUB_LABEL') || 'フィードバック';

  if (!token || !repo) {
    throw new Error('スクリプトプロパティに GITHUB_TOKEN / GITHUB_REPO を設定してください');
  }

  const itemResponses = e.response.getItemResponses();
  const timestamp = e.response.getTimestamp();
  const formattedTime = Utilities.formatDate(timestamp, 'Asia/Tokyo', 'yyyy-MM-dd HH:mm:ss');

  const bodyLines = [];
  itemResponses.forEach(function (itemResponse) {
    bodyLines.push('### ' + itemResponse.getItem().getTitle());
    bodyLines.push(String(itemResponse.getResponse()));
    bodyLines.push('');
  });
  bodyLines.push('---');
  bodyLines.push('送信日時: ' + formattedTime);

  const firstAnswer = itemResponses.length > 0 ? String(itemResponses[0].getResponse()) : '';
  const titleHint = firstAnswer.length > 0 && firstAnswer.length <= 30 ? firstAnswer : formattedTime;
  const title = 'フィードバック: ' + titleHint;

  const response = UrlFetchApp.fetch('https://api.github.com/repos/' + repo + '/issues', {
    method: 'post',
    contentType: 'application/json',
    headers: {
      Authorization: 'Bearer ' + token,
      Accept: 'application/vnd.github+json',
    },
    payload: JSON.stringify({
      title: title,
      body: bodyLines.join('\n'),
      labels: [label],
    }),
    muteHttpExceptions: true,
  });

  if (response.getResponseCode() >= 300) {
    console.error('GitHub Issue 作成に失敗しました: ' + response.getContentText());
    throw new Error('GitHub API error: ' + response.getResponseCode());
  }
}
