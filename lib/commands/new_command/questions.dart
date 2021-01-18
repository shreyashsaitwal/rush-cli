import 'package:rush_prompt/rush_prompt.dart';

class Questions {
  static List<Question> get questions {
    return [
      SimpleQuestion(
        question: 'Extension name',
        id: 'extName',
      ),
      SimpleQuestion(
        question: 'Organisation/Package name',
        id: 'org',
      ),
      SimpleQuestion(
        question: 'Author',
        id: 'author',
      ),
      SimpleQuestion(
        question: 'Version name',
        id: 'version',
      ),
    ];
  }
}
