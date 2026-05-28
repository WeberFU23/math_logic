import gymnasium as gym
import nesylink

env = gym.make("NesyLink-CollectKeyEasy-v0")
obs, info = env.reset(seed=0)

obs, reward, terminated, truncated, info = env.step(env.action_space.sample())

env.close()