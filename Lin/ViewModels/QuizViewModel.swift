//
//  QuizViewModel.swift
//  Lin
//
//  Created by Xinyi Zhuang on 06/03/2018.
//  Copyright © 2018 x52. All rights reserved.
//

import Foundation
import ReactiveSwift
import Result
import Firebase
import Alamofire

class QuizViewModel {
  public let currentQuestion: Signal<String?, NoError>
  public let testPassed: Signal<Void?, NoError>
  public let buttonState: Signal<(String, UIColor), NoError>
  public let cheatting: Signal<Bool, NoError>

  private let _wordList = MutableProperty([Word]())
  private let _viewDidLoad = MutableProperty(())
  private let _buttonPressed = MutableProperty(())
  private let _answer = MutableProperty<String?>(nil)
  private let _backupList = MutableProperty([Word]())
  private let _popViewController = MutableProperty(())

  init() {

    currentQuestion = _wordList.signal
      .combineLatest(with: _viewDidLoad.signal)
      .map { $0.0.first?.subtitle }
    testPassed = currentQuestion
      .map { $0 == nil ? () : nil }

    let testNotPassed = testPassed.map { $0 == nil }
    cheatting = testNotPassed.and(_popViewController.signal.map { true })

    let checkAnswer = Signal.combineLatest(
      _wordList.signal,
      _answer.signal.skipNil(),
      currentQuestion.skipNil()
      )
      .map { $0.0.check(answer: $0.1, for: $0.2) }

    let checkAnswerOnButtonPress = checkAnswer.sample(on: _buttonPressed.signal)
    buttonState = Signal.merge(
      checkAnswerOnButtonPress.filter { $0 == nil }.map { _ in ("回答错误，再试一次", .red) },
      _answer.signal.skipNil().map { _ in ("确定", .lightBlue) }
    )
    checkAnswerOnButtonPress.skipNil().observeValues {
      for (index, w) in self._wordList.value.enumerated() {
        guard w == $0 else {
          Analytics.logEvent(
            "SubmitedAnswer",
            parameters: ["english": $0.title, "chinese": $0.subtitle, "result": false]
          )
          continue
        }
        Analytics.logEvent(
          "SubmitedAnswer",
          parameters: ["english": $0.title, "chinese": $0.subtitle, "result": true])
        self._wordList.value.remove(at: index)
        self._backupList.value.append(w)
        return
      }
    }

    testPassed.skipNil().observeValues { [weak self] in
      self?._backupList.value.upload()
    }
    cheatting.observeValues {
      guard $0 == true else { return }
      sendSlackMessage("发现伟琳考试作弊")
    }

  }

  func viewDidLoad() {
    _viewDidLoad.value = ()
    Analytics.logEvent("StartedANewQuiz", parameters: ["date": Date().description])
  }
  func submit(answer: String?) { _answer.value = answer }
  func buttonPressed() { _buttonPressed.value = () }
  func startQuiz(for wordList: [Word]) { _wordList.value = wordList }
  func viewWillDisappear() { _popViewController.value = () }
}

extension Array where Element == Word {
  func check(answer: String, for question: String) -> Word? {
    for word in self {
      guard
        word.subtitle == question,
        word.title.lowercased().trimmingCharacters(in: .whitespaces) == answer.lowercased().trimmingCharacters(in: .whitespaces)
        else { continue }
      return word
    }
    return nil
  }

  func upload() {
    let ref = Database.database().reference().child(String(describing: Word.self))
    for w in self {
      ref.childByAutoId().setValue(w.dictionaryValue)
    }
    sendSlackMessage("伟琳刚刚背完了今天的单词")
  }
}

extension Word: Equatable {
  static func == (lhs: Word, rhs: Word) -> Bool {
    return lhs.title == rhs.title && lhs.subtitle == rhs.subtitle
  }

  var dictionaryValue: [String: String] {
    return [
      "english": title,
      "chinese": subtitle
    ]
  }
}

func sendSlackMessage(_ msg: String) {
  guard let hook = ProcessInfo.processInfo.environment["slack-webhook"] else { return }
  let payload = ["text": msg]
  Alamofire.request(hook, method: .post, parameters: payload, encoding: JSONEncoding.default, headers: nil)
    .responseString { rep in
      print(rep.description)
  }
}
