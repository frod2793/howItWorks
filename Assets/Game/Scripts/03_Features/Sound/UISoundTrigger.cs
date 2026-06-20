using System;
using UnityEngine;
using UnityEngine.UI;
using VContainer;
using VContainer.Unity;

namespace Features.Sound
{
    [RequireComponent(typeof(Button))]
    public class UISoundTrigger : MonoBehaviour
    {
        [SerializeField] private string m_soundKey = SoundKeys.Click;

        private ISoundService m_soundService;
        private Button m_button;

        private void Start()
        {
            m_button = GetComponent<Button>();
            if (m_button != null)
            {
                m_button.onClick.AddListener(PlaySound);
            }

            var projectScope = FindFirstObjectByType<ProjectLifetimeScope>();
            if (projectScope != null)
            {
                if (projectScope.Container != null)
                {
                    try
                    {
                        m_soundService = projectScope.Container.Resolve<ISoundService>();
                    }
                    catch (Exception)
                    {
                    }
                }
            }
        }

        private void PlaySound()
        {
            if (m_soundService != null)
            {
                m_soundService.PlaySFX(m_soundKey);
            }
        }
    }
}
