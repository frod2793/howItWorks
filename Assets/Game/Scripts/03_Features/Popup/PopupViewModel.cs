using System;

#region 뷰모델 (ViewModel)
/// <summary>
/// [설명]: 메시지, 자막, 그리고 연동될 애니메이션 정보를 담는 팝업 뷰모델입니다.
/// </summary>
public class PopupViewModel : IPopupViewModel
{
    #region 프로퍼티
    public string Message { get; private set; }
    public string Subtitle { get; private set; }
    public string AnimationKey { get; private set; }
    public event Action OnClosed;
    #endregion

    /// <summary>
    /// [설명]: 팝업 데이터를 초기화합니다.
    /// </summary>
    /// <param name="message">메인 메시지</param>
    /// <param name="subtitle">자막 내용 (선택)</param>
    /// <param name="animationKey">애니메이터 파라미터 또는 스테이트 이름 (선택)</param>
    public PopupViewModel(string message, string subtitle = "", string animationKey = "")
    {
        Message = message;
        Subtitle = subtitle;
        AnimationKey = animationKey;
    }

    #region 공개 메서드
    public void Close()
    {
        OnClosed?.Invoke();
    }
    #endregion
}
#endregion
