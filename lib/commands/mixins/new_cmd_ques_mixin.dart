import 'package:rush_prompt/rush_prompt.dart';

mixin QuestionsMixin {
  List<Question> get newCmdQues {
    return [
      SimpleQuestion(
        question: 'Extension name',
        id: 'name',
      ),
      SimpleQuestion(
        question: 'Organisation name',
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
      SimpleQuestion(
        question: 'License',
        id: 'license',
      ),
    ];
  }
}
