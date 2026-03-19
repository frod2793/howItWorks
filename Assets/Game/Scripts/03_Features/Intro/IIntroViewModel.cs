using System;

#region 뷰모델 (ViewModel)
/// <summary>
/// [설명]: 인트로 시퀀스의 상태와 명령을 정의하는 뷰모델 인터페이스입니다.
/// </summary>
public interface IIntroViewModel
{
    event Action<string, string> OnStoryChanged;
    event Action OnIntroFinished;
    event Action OnSkipRequested;

    string CurrentSpeaker { get; }
    string CurrentContent { get; }
    bool IsLastStep { get; }

    void StartIntro();
    void HandleNext();
}
#endregion
