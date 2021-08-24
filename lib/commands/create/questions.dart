import 'package:rush_prompt/rush_prompt.dart';

class Questions {
  static List<Question> get questions {
    return [
      SimpleQuestion(
        question: 'Organisation (package name)',
        id: 'org',
      ),
      MultipleChoiceQuestion(
        question: 'Language',
        options: ['Java', 'Kotlin'],
        id: 'lang',
      ),
    ];
  }
}
