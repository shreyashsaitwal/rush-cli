import 'questions/question.dart';

class RushPrompt {
  final List<Question> _questions = [];

  RushPrompt({List<Question> questions}) {
    if (questions != null) {
      _questions.addAll(questions);
    }
  }

  List<dynamic> askAll() {
    final answers = <List>[];
    _questions.forEach((ques) => answers.add(ques.ask()));
    return answers;
  }

  List<dynamic> askIndividual(Question ques) => ques.ask();

  List<dynamic> askQuestionAt(String id) {
    final ques = _questions.firstWhere((ques) => ques.id == id);
    _questions.remove(ques);
    return ques.ask();
  }

  void addQuestions(List<Question> ques) => _questions.addAll(ques);

  void removeQuestion(String id) =>
      _questions.removeWhere((ques) => ques.id == id);

  void insertQuestion(int atIndex, Question ques) =>
      _questions.insert(atIndex, ques);
}
