using System;

#region 뷰모델 (ViewModel)
/// <summary>
/// [설명]: 팝업의 메시지 상태, 자막, 애니메이션 상태 및 닫기 명령을 정의하는 인터페이스입니다.
/// </summary>
public interface IPopupViewModel
{
    string Message { get; }
    string Subtitle { get; }
    string AnimationKey { get; }
    event Action OnClosed;
    void Close();
}
#endregion
