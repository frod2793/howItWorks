using System;
using System.Collections.Generic;

#region 뷰모델 (ViewModel)
/// <summary>
/// [설명]: 인트로의 비즈니스 로직을 관리하며 상태를 뷰에 알리는 뷰모델입니다.
/// </summary>
public class IntroViewModel : IIntroViewModel
{
    #region 내부 필드
    private readonly IntroStoryDataDTO m_storyData;
    private int m_currentIndex = -1;
    #endregion

    #region 프로퍼티
    public event Action<string, string> OnStoryChanged;
    public event Action OnIntroFinished;
    public event Action OnSkipRequested;

    public string CurrentSpeaker => m_currentIndex >= 0 ? m_storyData.Steps[m_currentIndex].Speaker : string.Empty;
    public string CurrentContent => m_currentIndex >= 0 ? m_storyData.Steps[m_currentIndex].Content : string.Empty;
    public bool IsLastStep => m_currentIndex >= m_storyData.Steps.Count - 1;
    public float TypingSpeed => m_storyData?.TypingSpeed ?? 0.05f;
    #endregion

    /// <summary>
    /// [설명]: 뷰모델 생성 시 스토리 데이터를 주입받습니다.
    /// </summary>
    /// <param name="storyData">로드된 인트로 스토리 DTO</param>
    public IntroViewModel(IntroStoryDataDTO storyData)
    {
        m_storyData = storyData;
    }

    #region 공개 메서드
    /// <summary>
    /// [설명]: 인트로 시퀀스를 시작합니다.
    /// </summary>
    public void StartIntro()
    {
        if (m_storyData == null || m_storyData.Steps.Count == 0)
        {
            OnIntroFinished?.Invoke();
            return;
        }

        HandleNext();
    }

    /// <summary>
    /// [설명]: 다음 스토리 단계로 진행하거나, 타이핑 중이라면 스킵을 요청합니다.
    /// </summary>
    public void HandleNext()
    {
        m_currentIndex++;

        if (m_currentIndex < m_storyData.Steps.Count)
        {
            OnStoryChanged?.Invoke(CurrentSpeaker, CurrentContent);
        }
        else
        {
            OnIntroFinished?.Invoke();
        }
    }

    /// <summary>
    /// [설명]: 현재 진행 중인 타이핑 효과를 즉시 완료하도록 요청합니다.
    /// </summary>
    public void RequestSkip()
    {
        OnSkipRequested?.Invoke();
    }
    #endregion
}
#endregion
