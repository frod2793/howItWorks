using System;
using System.Threading;
using Cysharp.Threading.Tasks;
using DG.Tweening;
using Features.InGame;
using UnityEngine;
using TMPro;
using UnityEngine.UI;
using UnityEngine.InputSystem;
using VContainer;

public class IntroView : MonoBehaviour
{
    [Header("UI 요소")]
    [SerializeField] private TMP_Text m_speakerText;
    [SerializeField] private TMP_Text m_contentText;
    [SerializeField] private TypewriterEffect m_typewriter;

    [Header("테스트 및 디버그 설정")]
    [SerializeField] private bool m_skipIntro = false;

    private IIntroViewModel m_viewModel;
    private ISceneLoader m_sceneLoader;
    private ISoundService m_soundService;
    private bool m_canNextStep = false;
    private float m_typingSpeed = 0.05f;
    private CancellationTokenSource m_autoProceedCts;

    [Inject]
    public void Construct(
        IIntroViewModel viewModel, 
        ISceneLoader sceneLoader = null, 
        ISoundService soundService = null)
    {
        Setup(viewModel.TypingSpeed);
        Initialize(viewModel, sceneLoader, soundService);
    }

    public void Setup(float typingSpeed)
    {
        m_typingSpeed = typingSpeed;
        if (m_typewriter != null)
        {
            m_typewriter.TypingSpeed = m_typingSpeed;
        }
    }

    public void Initialize(IIntroViewModel viewModel, ISceneLoader sceneLoader = null, ISoundService soundService = null)
    {
        if (viewModel == null)
        {
            return;
        }

        m_viewModel = viewModel;
        m_skipIntro = viewModel.SkipIntro;
        m_sceneLoader = sceneLoader;
        m_soundService = soundService;

        if (m_skipIntro)
        {
            FinishIntroDeferred().Forget();
            return;
        }
        
        m_viewModel.OnStoryChanged += UpdateStory;
        m_viewModel.OnIntroFinished += FinishIntro;

        if (m_typewriter != null)
        {
            m_typewriter.OnStartTyping += () =>
            {
                if (m_soundService != null)
                {
                    m_soundService.PlayLoopSFX("Typing");
                }
            };
            m_typewriter.OnCompleteTyping += () =>
            {
                if (m_soundService != null)
                {
                    m_soundService.StopLoopSFX();
                }
            };
        }

        if (m_soundService != null)
        {
            m_soundService.StopBGM(1.0f);
        }

        StartIntroSequence().Forget();
    }

    private async UniTaskVoid StartIntroSequence()
    {
        await UniTask.Delay(TimeSpan.FromSeconds(1.0f), cancellationToken: this.GetCancellationTokenOnDestroy());
        m_viewModel.StartIntro();
    }

    public void func_OnSkipIntroClick()
    {
        CancelAutoProceed();
        FinishIntro();
    }

    private void Update()
    {
        if (m_viewModel == null)
        {
            return;
        }

        if (Keyboard.current != null)
        {
            if (Keyboard.current.escapeKey.wasPressedThisFrame)
            {
                func_OnSkipIntroClick();
                return;
            }

            if (Keyboard.current.spaceKey.wasPressedThisFrame)
            {
                if (m_typewriter != null && m_typewriter.IsTyping)
                {
                    m_typewriter.Skip();
                }
                else if (m_canNextStep)
                {
                    CancelAutoProceed();
                    ProceedNext();
                }
            }
        }
    }

    private void UpdateStory(string speaker, string content)
    {
        if (m_speakerText != null)
        {
            m_speakerText.text = speaker;
        }
        
        CancelAutoProceed();

        m_canNextStep = false;
        
        ResetFade();

        if (m_typewriter != null)
        {
            m_typewriter.Play(m_contentText, content, () =>
            {
                m_canNextStep = true;
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
        if (m_contentText != null)
        {
            m_contentText.alpha = 1f;
        }
        if (m_speakerText != null)
        {
            m_speakerText.alpha = 1f;
        }
    }

    private async UniTaskVoid StartAutoProceedSequence()
    {
        m_autoProceedCts = new CancellationTokenSource();
        var token = m_autoProceedCts.Token;

        try
        {
            await UniTask.Delay(TimeSpan.FromSeconds(2.0f), cancellationToken: token);

            if (m_contentText != null)
            {
                await m_contentText.DOFade(0f, 1.0f).ToUniTask(cancellationToken: token);
            }

            ProceedNext();
        }
        catch (OperationCanceledException)
        {
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
        if (m_viewModel != null)
        {
            m_viewModel.HandleNext();
        }
    }

    private async UniTaskVoid FinishIntroDeferred()
    {
        await UniTask.Yield();
        FinishIntro();
    }

    private void FinishIntro()
    {
        Debug.Log("[IntroView] 인트로 뷰 비활성화 및 다이얼로그 시스템 시작");
        
        gameObject.SetActive(false);

        if (m_viewModel != null)
        {
            m_viewModel.FinishIntro();
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
}
