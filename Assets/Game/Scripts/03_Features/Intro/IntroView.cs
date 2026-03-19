using System.Threading;
using Cysharp.Threading.Tasks;
using DG.Tweening;
using UnityEngine;
using TMPro;
using UnityEngine.UI;
using UnityEngine.InputSystem;

#region 뷰 (View)
/// <summary>
/// [설명]: 인트로 화면의 UI와 이벤트를 관리하는 뷰 클래스입니다.
/// </summary>
public class IntroView : MonoBehaviour
{
    #region 에디터 설정
    [Header("UI Elements")]
    [SerializeField] private TMP_Text m_speakerText;
    [SerializeField] private TMP_Text m_contentText;
    [SerializeField] private TypewriterEffect m_typewriter;
    #endregion

    #region 내부 필드
    private IIntroViewModel m_viewModel;
    private ISceneLoader m_sceneLoader;
    private ISoundService m_soundService;
    private bool m_canNextStep = false;
    private float m_typingSpeed = 0.05f;
    private CancellationTokenSource m_autoProceedCts;
    #endregion

    #region 초기화 및 바인딩 로직
    /// <summary>
    /// [설명]: 인트로 설정을 수행합니다.
    /// </summary>
    public void Setup(float typingSpeed)
    {
        m_typingSpeed = typingSpeed;
        if (m_typewriter != null) m_typewriter.TypingSpeed = m_typingSpeed;
    }

    /// <summary>
    /// [설명]: 뷰모델 및 전역 서비스가 주입되며 초기화됩니다.
    /// </summary>
    /// <param name="viewModel">인트로 뷰모델</param>
    /// <param name="sceneLoader">씬 로더 서비스 (DI)</param>
    /// <param name="soundService">사운드 서비스 (DI)</param>
    public void Initialize(IIntroViewModel viewModel, ISceneLoader sceneLoader = null, ISoundService soundService = null)
    {
        if (viewModel == null) return;

        m_viewModel = viewModel;
        m_sceneLoader = sceneLoader;
        m_soundService = soundService;
        
        m_viewModel.OnStoryChanged += UpdateStory;
        m_viewModel.OnIntroFinished += FinishIntro;

        // 타이핑 사운드 이벤트 연결
        if (m_typewriter != null)
        {
            m_typewriter.OnStartTyping += () => m_soundService?.PlayLoopSFX("Typing");
            m_typewriter.OnCompleteTyping += () => m_soundService?.StopLoopSFX();
        }

        // 인트로 진입 시 기존에 재생 중이던 BGM이 있다면 자연스럽게 페이드 아웃
        m_soundService?.StopBGM(1.0f);

        StartIntroSequence().Forget();
    }

    private async UniTaskVoid StartIntroSequence()
    {
        // 인트로 시작 전 1초 지연 (요구사항)
        await UniTask.Delay(System.TimeSpan.FromSeconds(1.0f), cancellationToken: this.GetCancellationTokenOnDestroy());
        m_viewModel.StartIntro();
    }
    #endregion

    #region 유니티 생명주기
    private void Update()
    {
        if (m_viewModel == null) return;

        // 스페이스바 입력 처리 (New Input System 방식)
        if (Keyboard.current != null && Keyboard.current.spaceKey.wasPressedThisFrame)
        {
            if (m_typewriter != null && m_typewriter.IsTyping)
            {
                // 타이핑 중이면 스킵
                m_typewriter.Skip();
            }
            else if (m_canNextStep)
            {
                // 타이핑 완료 후면 다음으로 (자동 진행 중이라면 취소 후 즉시 진행)
                CancelAutoProceed();
                ProceedNext();
            }
        }
    }
    #endregion

    #region 내부 로직
    private void UpdateStory(string speaker, string content)
    {
        if (m_speakerText != null) m_speakerText.text = speaker;
        
        // 이전 자동 진행 취소
        CancelAutoProceed();

        m_canNextStep = false;
        
        // 페이드 인 (초기화)
        ResetFade();

        if (m_typewriter != null)
        {
            m_typewriter.Play(m_contentText, content, () =>
            {
                m_canNextStep = true;
                // 자동 진행 시퀀스 시작
                StartAutoProceedSequence().Forget();
            }).Forget();
        }
        else if (m_contentText != null)
        {
            m_contentText.text = content;
            m_canNextStep = true;
            StartAutoProceedSequence().Forget();
        }
    }

    private void ResetFade()
    {
        if (m_contentText != null) m_contentText.alpha = 1f;
        if (m_speakerText != null) m_speakerText.alpha = 1f;
    }

    private async UniTaskVoid StartAutoProceedSequence()
    {
        m_autoProceedCts = new CancellationTokenSource();
        var token = m_autoProceedCts.Token;

        try
        {
            // 1. 출력 후 대기 (가독성을 위한 시간 확보)
            await UniTask.Delay(System.TimeSpan.FromSeconds(2.0f), cancellationToken: token);

            // 2. 페이드 아웃 연출 (DOTween 활용)
            if (m_contentText != null)
            {
                await m_contentText.DOFade(0f, 1.0f).ToUniTask(cancellationToken: token);
            }

            // 3. 다음 단계로 진행
            ProceedNext();
        }
        catch (System.OperationCanceledException)
        {
            // 수동 진행(스페이스바) 등으로 취소됨
        }
    }

    private void CancelAutoProceed()
    {
        if (m_autoProceedCts != null)
        {
            m_autoProceedCts.Cancel();
            m_autoProceedCts.Dispose();
            m_autoProceedCts = null;
        }
    }

    private void ProceedNext()
    {
        m_canNextStep = false;
        m_viewModel.HandleNext();
    }

    private void FinishIntro()
    {
        Debug.Log("[IntroView] 인트로가 종료되었습니다. 타이틀 씬으로 전환합니다.");
        
        if (m_sceneLoader != null)
        {
            // 타이틀 씬(Title)으로 부드럽게 전환
            m_sceneLoader.LoadScene("Title", 1.0f);
        }
        else
        {
            Debug.LogWarning("[IntroView] SceneLoader가 주입되지 않았습니다. 수동으로 씬을 전환하세요.");
        }
    }

    private void OnDestroy()
    {
        if (m_viewModel != null)
        {
            m_viewModel.OnStoryChanged -= UpdateStory;
            m_viewModel.OnIntroFinished -= FinishIntro;
        }
        
        CancelAutoProceed();
    }
    #endregion
}
#endregion
