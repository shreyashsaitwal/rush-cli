import 'questions/question.dart';

class RushPrompt {
  RushPrompt({List<Question> questions}) {
    if (questions != null) {
      _questions.addAll(questions);
    }
  }

  final List<Question> _questions = [];

  List askAll() {
    final answers = [];
    _questions.forEach((ques) => answers.add(ques.ask()));
    return answers;
  }

  List askIndividual(Question ques) => ques.ask();

  List askQuestionAt(String id) {
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
