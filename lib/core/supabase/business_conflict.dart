// PT409 is an application conflict, never an engine serialization failure.
// Narrow legacy compatibility supports an independently deployed older backend.
bool isBusinessConflict(String? code, String message) =>
    code == 'PT409' ||
    (code == '40001' &&
        const {
          'expense changed',
          'list access changed',
          'list changed',
          'list item changed',
          'moderation case changed',
          'moderation restriction changed',
          'relationship changed',
          'settlement changed',
          'split changed',
          'template category changed',
          'template changed',
          'template send changed',
        }.contains(message));
